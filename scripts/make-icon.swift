// Generates WriteMD/Resources/AppIcon.icns. Usage: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: art occupies ~80% of the canvas
    let art = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let body = NSBezierPath(roundedRect: art, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.white.setFill(); body.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.45, blue: 0.95, alpha: 1),
                        NSColor(srgbRed: 0.13, green: 0.20, blue: 0.62, alpha: 1)])!.draw(in: body, angle: -90)

    // Big "W", a heading-style underline bar, and a caret: "write, rendered".
    let font = NSFont.systemFont(ofSize: s * 0.46, weight: .heavy)
    let str = NSAttributedString(string: "W", attributes: [.font: font, .foregroundColor: NSColor.white])
    let sz = str.size()
    str.draw(at: NSPoint(x: art.midX - sz.width / 2 - s * 0.03, y: art.midY - sz.height / 2 + s * 0.045))
    NSColor(white: 1, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: art.minX + art.width * 0.2, y: art.minY + art.height * 0.2,
                                     width: art.width * 0.42, height: s * 0.035), xRadius: s * 0.0175, yRadius: s * 0.0175).fill()
    NSColor(srgbRed: 1.0, green: 0.78, blue: 0.25, alpha: 1).setFill()   // the text caret
    NSBezierPath(roundedRect: NSRect(x: art.minX + art.width * 0.68, y: art.minY + art.height * 0.17,
                                     width: s * 0.035, height: s * 0.10), xRadius: s * 0.0175, yRadius: s * 0.0175).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = NSTemporaryDirectory() + "WriteMD.iconset"
try? FileManager.default.removeItem(atPath: dir)
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "WriteMD/Resources/AppIcon.icns"
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir, "-o", out]; try! p.run(); p.waitUntilExit()
print("wrote", out)
try? render(512).write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "icon-preview.png"))
