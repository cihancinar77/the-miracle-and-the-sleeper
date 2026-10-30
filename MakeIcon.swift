// Renders the moon app icon into an .iconset folder.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    NSGradient(colors: [NSColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1),
                        NSColor(red: 0.33, green: 0.06, blue: 0.08, alpha: 1)])!.draw(in: shape, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(red: 1, green: 0.62, blue: 0.22, alpha: 0.45), .clear])!
        .draw(fromCenter: NSPoint(x: s / 2, y: s * 0.55), radius: 0,
              toCenter: NSPoint(x: s / 2, y: s * 0.55), radius: s * 0.42, options: [])
    NSGraphicsContext.restoreGraphicsState()
    shape.lineWidth = s * 0.018
    NSColor(red: 0.85, green: 0.66, blue: 0.27, alpha: 1).setStroke()
    shape.stroke()

    func symbol(_ name: String, _ pt: CGFloat, _ colors: [NSColor], center: NSPoint) {
        let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .regular)
            .applying(.init(paletteColors: colors))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        img.draw(in: NSRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2,
                            width: img.size.width, height: img.size.height))
    }
    symbol("moon.stars.fill", s * 0.4, [NSColor(red: 0.95, green: 0.83, blue: 0.54, alpha: 1),
                                        NSColor(red: 1, green: 0.72, blue: 0.3, alpha: 1)],
           center: NSPoint(x: s / 2, y: s / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
