// Generates the app icon: swift make-icon.swift
// Writes Resources/AppIcon.icns: a bar chart in the four memory breakdown colors, seen through a glass lens.
import AppKit

let canvas: CGFloat = 1024

func drawIcon() {
    // Body (macOS icon grid: an 824 rounded square on a 1024 canvas)
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(red: 0.18, green: 0.24, blue: 0.42, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.08, blue: 0.17, alpha: 1))!
        .draw(in: bodyPath, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()

    // Bar chart (App, Wired, Compressed, Cache)
    func drawBars() {
        let bars: [(CGFloat, NSColor)] = [
            (420, .systemBlue), (290, .systemOrange), (220, .systemPurple), (340, .systemTeal),
        ]
        for (i, bar) in bars.enumerated() {
            let rect = NSRect(x: 215 + CGFloat(i) * 155, y: 230, width: 115, height: bar.0)
            let path = NSBezierPath(roundedRect: rect, xRadius: 40, yRadius: 40)
            NSGradient(starting: bar.1.blended(withFraction: 0.25, of: .white)!, ending: bar.1)!
                .draw(in: path, angle: -90)
        }
    }
    drawBars()

    // Lens (handle, magnified bars, glass, rim), with the handle pointing down-right
    let center = NSPoint(x: 455, y: 545)
    let r: CGFloat = 190
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: center.x + r * 0.72, y: center.y - r * 0.72))
    handle.line(to: NSPoint(x: center.x + r * 1.5, y: center.y - r * 1.5))
    handle.lineWidth = 62
    handle.lineCapStyle = .round
    NSColor.white.setStroke()
    handle.stroke()

    let lens = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    NSGraphicsContext.saveGraphicsState()
    lens.addClip()
    NSGradient(starting: NSColor(red: 0.20, green: 0.27, blue: 0.47, alpha: 1),
               ending: NSColor(red: 0.08, green: 0.12, blue: 0.24, alpha: 1))!
        .draw(in: lens, angle: -90)
    let zoom = NSAffineTransform()
    zoom.translateX(by: center.x, yBy: center.y)
    zoom.scale(by: 1.4)
    zoom.translateX(by: -center.x, yBy: -center.y)
    zoom.concat()
    drawBars()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor.white.withAlphaComponent(0.28),
               ending: NSColor.white.withAlphaComponent(0.0))!
        .draw(in: lens, angle: -60)
    lens.lineWidth = 34
    NSColor.white.setStroke()
    lens.stroke()

    // Reflection on the lens
    let glint = NSBezierPath()
    glint.appendArc(withCenter: center, radius: r - 62, startAngle: 105, endAngle: 160)
    glint.lineWidth = 22
    glint.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.7).setStroke()
    glint.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let scale = CGFloat(size) / canvas
    ctx.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
print(task.terminationStatus == 0 ? "written: Resources/AppIcon.icns" : "iconutil failed")
