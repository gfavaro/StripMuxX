import AppKit
import Common

/// The menu bar icon: a strip of columns, the middle one in view.
enum MenuBarLayoutIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(monochrome: Bool, tint: NSColor? = nil) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let color = tint ?? (monochrome ? NSColor.black : NSColor.controlAccentColor)
            color.setStroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect.insetBy(dx: 0.2, dy: 0.2)).addClip()

            let neighbor = NSBezierPath(roundedRect: NSRect(x: -4.8, y: 3.0, width: 8.0, height: 12.0), xRadius: 1.8, yRadius: 1.8)
            let center = NSBezierPath(roundedRect: NSRect(x: 5.4, y: 1.6, width: 7.2, height: 14.8), xRadius: 2.0, yRadius: 2.0)
            let next = NSBezierPath(roundedRect: NSRect(x: 14.8, y: 3.0, width: 8.0, height: 12.0), xRadius: 1.8, yRadius: 1.8)
            for (path, width) in [(neighbor, 1.1), (center, 1.4), (next, 1.1)] {
                path.lineWidth = width
                path.lineJoinStyle = .round
                path.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = monochrome && tint == nil
        return image
    }
}

func menuBarIconImage(enabled: Bool, appearance: MenuBarIconAppearance, keyboardTint: NSColor? = nil) -> NSImage? {
    guard enabled else {
        return NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "StripMuxX disabled")
    }
    return MenuBarLayoutIcon.image(monochrome: appearance != .color, tint: keyboardTint)
}
