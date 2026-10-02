// Draws the app icon into an .iconset folder. scripts/build-app.sh runs this,
// then turns the folder into AppIcon.icns with iconutil.
//
//   swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Two Dock shelves on a blue tile: a faded saved layout above the live one.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    // Apple's icon grid: an 824pt body centred on a 1024pt canvas.
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x5AA2FF), ending: color(0x1E4FD8))!.draw(in: body, angle: -90)

    func shelf(y: CGFloat, tiles: [NSColor], shelfAlpha: CGFloat) {
        color(0xFFFFFF, alpha: shelfAlpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: 190 * s, y: y * s, width: 644 * s, height: 190 * s),
                     xRadius: 52 * s, yRadius: 52 * s).fill()
        for (index, tileColor) in tiles.enumerated() {
            tileColor.setFill()
            let x = 232 + CGFloat(index) * 148
            NSBezierPath(roundedRect: NSRect(x: x * s, y: (y + 37) * s, width: 116 * s, height: 116 * s),
                         xRadius: 28 * s, yRadius: 28 * s).fill()
        }
    }

    let ghost = color(0xFFFFFF, alpha: 0.45)
    shelf(y: 560, tiles: [ghost, ghost, ghost, ghost], shelfAlpha: 0.14)
    shelf(y: 250, tiles: [color(0xFFB340), color(0x34C759), color(0xFF5E57), color(0xFFFFFF)], shelfAlpha: 0.3)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
