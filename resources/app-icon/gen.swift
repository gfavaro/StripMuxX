import AppKit

// StripMuxX app icon: a screen showing a strip of columns, the focused one centred, neighbours cut by the edges,
// echoing the menu bar icon. Run from this folder:  swift gen.swift
// It writes the ten PNGs of the app icon set and icon.png (1024 px, used by the README). The continuous
// corner curve is the same one the minimap draws (continuousRoundedRect in the app's sources).
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    let r = min(radius, min(rect.width, rect.height) / (2 * 1.52866483))
    guard r > 0 else { return NSBezierPath(rect: rect) }
    let path = NSBezierPath()
    func point(_ x: CGFloat, _ y: CGFloat, corner: Int) -> CGPoint {
        switch corner {
            case 0: CGPoint(x: rect.maxX - x * r, y: rect.minY + y * r)
            case 1: CGPoint(x: rect.maxX - y * r, y: rect.maxY - x * r)
            case 2: CGPoint(x: rect.minX + x * r, y: rect.maxY - y * r)
            default: CGPoint(x: rect.minX + y * r, y: rect.minY + x * r)
        }
    }
    path.move(to: point(0, 1.52866483, corner: 3))
    for corner in 0 ..< 4 {
        path.line(to: point(1.52866483, 0, corner: corner))
        path.curve(to: point(0.63149379, 0.07491139, corner: corner), controlPoint1: point(1.08849296, 0, corner: corner), controlPoint2: point(0.86840694, 0, corner: corner))
        path.curve(to: point(0.07491139, 0.63149379, corner: corner), controlPoint1: point(0.37282383, 0.16906013, corner: corner), controlPoint2: point(0.16906013, 0.37282383, corner: corner))
        path.curve(to: point(0, 1.52866483, corner: corner), controlPoint1: point(0, 0.86840694, corner: corner), controlPoint2: point(0, 1.08849296, corner: corner))
    }
    path.close()
    return path
}

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

struct Palette { let top: NSColor, bottom: NSColor }
let blue = Palette(top: c(0.47, 0.82, 0.95), bottom: c(0.26, 0.69, 0.86))
let orange = Palette(top: c(0.98, 0.76, 0.38), bottom: c(0.92, 0.66, 0.02))
let green = Palette(top: c(0.58, 0.92, 0.65), bottom: c(0.44, 0.83, 0.52))
let pink = Palette(top: c(0.96, 0.42, 0.62), bottom: c(0.89, 0.12, 0.45))
let purple = Palette(top: c(0.78, 0.56, 0.96), bottom: c(0.62, 0.36, 0.90))

/// Draws the icon into a 1024-unit square in the current context. `small` drops the title bars and the
/// stacked windows so the shapes stay readable at 16 and 32 points.
func drawIcon(small: Bool) {
    // Body on the macOS grid: 824 inside 1024.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = continuousRoundedRect(body, radius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = small ? 14 : 26; shadow.shadowOffset = CGSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.set()
    c(0.12, 0.13, 0.18).setFill(); bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: c(0.37, 0.41, 0.50), ending: c(0.10, 0.11, 0.16))!.draw(in: bodyPath, angle: -90)
    c(1, 1, 1, 0.18).setStroke(); bodyPath.lineWidth = 3; bodyPath.stroke()

    // The screen.
    let screen = small ? CGRect(x: 150, y: 215, width: 724, height: 594) : CGRect(x: 160, y: 235, width: 704, height: 554)
    let screenPath = continuousRoundedRect(screen, radius: small ? 70 : 56)
    c(0.07, 0.08, 0.09).setFill(); screenPath.fill()
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()

    func window(_ rect: CGRect, _ p: Palette, bar: Bool = true, radius: CGFloat = 30) {
        let path = continuousRoundedRect(rect, radius: radius)
        NSGradient(starting: p.top, ending: p.bottom)!.draw(in: path, angle: -90)
        guard bar, !small else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        c(0, 0, 0, 0.14).setFill()
        CGRect(x: rect.minX, y: rect.maxY - 46, width: rect.width, height: 46).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    let pad: CGFloat = small ? 22 : 18
    let top = screen.maxY - pad, bottom = screen.minY + pad
    let h = top - bottom
    let x0 = screen.minX
    if small {
        // Three columns: the focused one wide and centred, its neighbours cut by the screen's edges.
        window(CGRect(x: x0 - 70, y: bottom, width: 190, height: h), green, bar: false, radius: 40)
        window(CGRect(x: x0 + 140, y: bottom, width: 440, height: h), blue, bar: false, radius: 40)
        window(CGRect(x: x0 + 600, y: bottom, width: 190, height: h), orange, bar: false, radius: 40)
    } else {
        window(CGRect(x: x0 - 74, y: bottom, width: 190, height: h), green)
        // The focused column, in the middle, with a ring.
        let focus = CGRect(x: x0 + 134, y: bottom, width: 348, height: h)
        window(focus, blue)
        let ring = continuousRoundedRect(focus.insetBy(dx: -9, dy: -9), radius: 38)
        c(1, 1, 1, 0.92).setStroke(); ring.lineWidth = 8; ring.stroke()
        // A stack of two windows.
        let stackX = x0 + 500, stackW: CGFloat = 150, gap: CGFloat = 16
        let half = (h - gap) / 2
        window(CGRect(x: stackX, y: bottom + half + gap, width: stackW, height: half), orange)
        window(CGRect(x: stackX, y: bottom, width: stackW, height: half), pink)
        window(CGRect(x: x0 + 666, y: bottom, width: 190, height: h), purple)
    }
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int, small: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)
    let t = NSAffineTransform(); t.scale(by: CGFloat(size) / 1024); t.concat()
    ctx.imageInterpolation = .high
    drawIcon(small: small)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, _ path: String) { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }

let appIconSet = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "../Assets.xcassets/AppIcon.appiconset"
let preview = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon.png"

// The slots of the icon set and the pixels each needs. 16 and 32 point slots (up to 64 px) get the
// simpler drawing: no title bars and no stacked windows, so the shapes stay readable.
let slots: [(file: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for slot in slots { png(render(size: slot.pixels, small: slot.pixels <= 64), "\(appIconSet)/\(slot.file)") }
png(render(size: 1024, small: false), preview)
print("wrote \(slots.count) icons to \(appIconSet) and \(preview)")
