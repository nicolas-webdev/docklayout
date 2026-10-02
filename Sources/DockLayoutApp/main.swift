import AppKit

enum StatusIcon {
    /// A Dock outline with four tiles, drawn as a template image so it
    /// follows the menu bar's light and dark appearance.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let bar = NSBezierPath(roundedRect: NSRect(x: 1, y: 2.5, width: 16, height: 6), xRadius: 1.6, yRadius: 1.6)
            bar.lineWidth = 1.3
            bar.stroke()
            for index in 0..<4 {
                let x = 2.6 + CGFloat(index) * 3.7
                NSBezierPath(rect: NSRect(x: x, y: 4.1, width: 2.2, height: 2.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
