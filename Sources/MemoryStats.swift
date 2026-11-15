import AppKit
import Darwin

enum PressureLevel: Int32 {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Warning")
        case .critical: String(localized: "Critical")
        }
    }

    var symbol: String {
        switch self {
        case .normal: "memorychip"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}

/// The same categories as Activity Monitor's Memory tab
struct SystemMemory {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cachedFiles: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: PressureLevel = .normal

    var used: UInt64 { app + wired + compressed }
}

struct AppUsage: Identifiable {
    let id: String          // Path of the .app, or the process name
    let name: String
    let footprint: UInt64   // Sum of phys_footprint (Activity Monitor's Memory column)
    let processCount: Int
    let runningApp: NSRunningApplication?
}

enum MemoryReader {
    static func system() -> SystemMemory {
        var m = SystemMemory()
        m.total = sysctlValue("hw.memsize", as: UInt64.self) ?? 0

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let anon = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            m.app = (anon - min(anon, purgeable)) * page
            m.wired = UInt64(stats.wire_count) * page
            m.compressed = UInt64(stats.compressor_page_count) * page
            m.cachedFiles = (UInt64(stats.external_page_count) + purgeable) * page
            m.free = UInt64(stats.free_count) * page
        }

        if let swap = sysctlValue("vm.swapusage", as: xsw_usage.self) {
            m.swapUsed = swap.xsu_used
        }
        if let raw = sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self),
           let level = PressureLevel(rawValue: raw) {
            m.pressure = level
        }
        return m
    }

    /// Memory of every process, grouped by the .app it belongs to (browser helpers count towards the browser)
    static func topApps(limit: Int) -> [AppUsage] {
        let n = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) / MemoryLayout<pid_t>.size + 32)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let pidCount = Int(bytes) / MemoryLayout<pid_t>.size

        var groups: [String: (name: String, bytes: UInt64, count: Int)] = [:]
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)

        for pid in pids.prefix(pidCount) where pid > 0 {
            var info = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard r == 0 else { continue }  // Root processes and the like can't be read without privileges

            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""
            let (key, name) = groupKey(for: path, pid: pid)

            var g = groups[key] ?? (name, 0, 0)
            g.bytes += info.ri_phys_footprint
            g.count += 1
            groups[key] = g
        }

        let running = NSWorkspace.shared.runningApplications
        return groups
            .sorted { $0.value.bytes > $1.value.bytes }
            .prefix(limit)
            .map { key, g in
                let app = key.hasSuffix(".app") ? running.first { $0.bundleURL?.path == key } : nil
                return AppUsage(id: key, name: app?.localizedName ?? g.name,
                                footprint: g.bytes, processCount: g.count, runningApp: app)
            }
    }

    /// Finds the outermost .app in the path
    private static func groupKey(for path: String, pid: pid_t) -> (String, String) {
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let name = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return (appPath, name)
        }
        if !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            return (name, name)
        }
        return ("pid-\(pid)", "pid \(pid)")
    }

    private static func sysctlValue<T>(_ name: String, as: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard sysctlbyname(name, ptr, &size, nil, 0) == 0 else { return nil }
        return ptr.pointee
    }
}

func formatBytes(_ b: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
}
