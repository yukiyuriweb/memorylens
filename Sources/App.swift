import SwiftUI

@main
struct MemoryLensApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(systemName: model.system.pressure.symbol)
            Text(model.remainingText)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var system = SystemMemory()
    @Published var apps: [AppUsage] = []
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Physical memory minus used: free, cached files and anything else available right away
    var remaining: UInt64 { system.total - min(system.total, system.used) }

    var remainingText: String {
        String(format: "%.1f GB", Double(remaining) / 1_073_741_824)
    }

    func refresh() {
        system = MemoryReader.system()
        apps = MemoryReader.topApps(limit: 10)
    }
}

// MARK: - Colors

extension Color {
    static let appMem = Color.blue
    static let wiredMem = Color.orange
    static let compressedMem = Color.purple
    static let cachedMem = Color.teal
}

extension PressureLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                HeaderCard(model: model)
                BreakdownCard(system: model.system)
                AppsCard(apps: model.apps)
                Footer()
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}

/// Remaining memory, pressure and the breakdown bar
struct HeaderCard: View {
    @ObservedObject var model: Model

    var body: some View {
        let s = model.system
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(model.remaining))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("Physical memory \(formatBytes(s.total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PressureBadge(level: s.pressure)
            }

            UsageBar(system: s)

            HStack(spacing: 12) {
                LegendDot(color: .appMem, title: "App")
                LegendDot(color: .wiredMem, title: "Wired")
                LegendDot(color: .compressedMem, title: "Compressed")
                LegendDot(color: .cachedMem, title: "Cache")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .animation(.smooth, value: model.remaining)
    }
}

struct PressureBadge: View {
    let level: PressureLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(level.color.opacity(0.7)), in: .capsule)
            .help("Memory pressure")
    }
}

struct LegendDot: View {
    let color: Color
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// The physical memory breakdown as a single bar
struct UsageBar: View {
    let system: SystemMemory

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(system.total), 1)
            let parts: [(UInt64, Color)] = [
                (system.app, .appMem), (system.wired, .wiredMem),
                (system.compressed, .compressedMem), (system.cachedFiles, .cachedMem),
            ]
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    Capsule()
                        .fill(parts[i].1.gradient)
                        .frame(width: max(0, geo.size.width * Double(parts[i].0) / total - 2))
                }
                Spacer(minLength: 0)
            }
            .padding(2)
            .background(.primary.opacity(0.08), in: .capsule)
        }
        .frame(height: 14)
        .animation(.smooth, value: system.used)
    }
}

/// The breakdown in numbers, as two columns of tiles
struct BreakdownCard: View {
    let system: SystemMemory

    var body: some View {
        let s = system
        Grid(horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                StatCell(title: "Memory Used", bytes: s.used, color: .primary)
                StatCell(title: "App Memory", bytes: s.app, color: .appMem)
            }
            GridRow {
                StatCell(title: "Wired Memory", bytes: s.wired, color: .wiredMem)
                StatCell(title: "Compressed", bytes: s.compressed, color: .compressedMem)
            }
            GridRow {
                StatCell(title: "Cached Files", bytes: s.cachedFiles, color: .cachedMem)
                StatCell(title: "Free", bytes: s.free, color: .secondary)
            }
            GridRow {
                StatCell(title: "Swap Used", bytes: s.swapUsed, color: .secondary)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct StatCell: View {
    let title: LocalizedStringKey
    let bytes: UInt64
    let color: Color

    var body: some View {
        // Title above the value, so English titles get the full width of the cell
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(formatBytes(bytes))
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .padding(.leading, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The apps using the most memory
struct AppsCard: View {
    let apps: [AppUsage]

    var body: some View {
        let maxBytes = Double(apps.first?.footprint ?? 1)
        VStack(alignment: .leading, spacing: 2) {
            Text("Apps using the most memory")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(apps) { app in
                AppRow(app: app, ratio: Double(app.footprint) / max(maxBytes, 1))
            }

            Text("Processes running as root are not counted.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        .padding(8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

struct AppRow: View {
    let app: AppUsage
    let ratio: Double
    @State private var hovering = false

    private var quittable: NSRunningApplication? {
        guard let r = app.runningApp, r != NSRunningApplication.current else { return nil }
        return r
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = app.runningApp?.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                        .padding(2)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(app.name).font(.callout).lineLimit(1)
                    if app.processCount > 1 {
                        Text("×\(app.processCount)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                // Relative to the app using the most
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.08))
                        Capsule()
                            .fill(Color.appMem.opacity(0.55).gradient)
                            .frame(width: max(4, geo.size.width * ratio))
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 6)

            if hovering, let running = quittable {
                Button {
                    running.terminate()
                } label: {
                    Label("Quit", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Quit \(app.name)")
                .transition(.opacity.combined(with: .scale))
            } else {
                Text(formatBytes(app.footprint))
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(.rect)
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
    }
}

struct Footer: View {
    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Label("Activity Monitor", systemImage: "waveform.path.ecg")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }
}
