import AppKit

// A two-resolution TIFF keeps Finder's background sharp without changing its logical size.
let width = 660
let height = 420
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    // bitmap.size already makes AppKit scale this context for Retina pixels.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let ink = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.24, alpha: 1)
    let muted = NSColor(calibratedRed: 0.45, green: 0.46, blue: 0.55, alpha: 1)
    let accent = NSColor(calibratedRed: 0.43, green: 0.38, blue: 0.86, alpha: 1)
    NSGradient(starting: NSColor(calibratedRed: 0.98, green: 0.98, blue: 1, alpha: 1),
        ending: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.99, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
    func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
              weight: NSFont.Weight = .regular, color: NSColor, centered: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 42), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }
    text("GitHub Star", x: 42, y: 34, width: 420, size: 29, weight: .semibold, color: ink)
    text("发现开源灵感，从一颗 Star 开始。", x: 43, y: 78, width: 450, size: 13, color: muted)
    accent.withAlphaComponent(0.09).setFill()
    NSBezierPath(roundedRect: NSRect(x: 549, y: 39, width: 69, height: 26), xRadius: 13, yRadius: 13).fill()
    text("macOS", x: 549, y: 44, width: 69, size: 11, weight: .medium, color: accent, centered: true)
    // Finder places the actual app and Applications icons over these subtle pads.
    for x in [CGFloat(115), CGFloat(415)] {
        NSColor.white.withAlphaComponent(0.65).setFill()
        let pad = NSBezierPath(roundedRect: NSRect(x: x, y: 155, width: 130, height: 130), xRadius: 30, yRadius: 30)
        pad.fill()
        accent.withAlphaComponent(0.08).setStroke()
        pad.lineWidth = 1
        pad.stroke()
    }
    accent.withAlphaComponent(0.75).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 292, y: 219))
    arrow.line(to: NSPoint(x: 365, y: 219))
    arrow.move(to: NSPoint(x: 356, y: 210))
    arrow.line(to: NSPoint(x: 365, y: 219))
    arrow.line(to: NSPoint(x: 356, y: 228))
    arrow.stroke()
    text("拖入右侧文件夹即可安装", x: 210, y: 331, width: 240, size: 15, weight: .medium, color: ink, centered: true)
    text("安装后，在「应用程序」中打开 GitHub Star", x: 120, y: 359, width: 420, size: 12, color: muted, centered: true)
    NSGraphicsContext.restoreGraphicsState()
    let filename = scale == 1 ? "DMGBackground-preview.png" : "DMGBackground@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
