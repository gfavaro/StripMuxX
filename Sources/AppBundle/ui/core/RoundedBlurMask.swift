import AppKit

/// Corner radius of the floating overlay panels (the minimap and the shortcut cheat sheet).
let overlayPanelCornerRadius: CGFloat = 18

/// A stretchable mask that rounds a blur view. Rounding the view's layer clips what is drawn on it, but
/// the blur WindowServer composites behind the window is shaped by the view, so it stays a rectangle
/// whose corners show as square patches outside the curve unless the view has a mask.
@MainActor
func roundedBlurMask(radius: CGFloat) -> NSImage {
    // A continuous corner reaches 1.53 radii along each edge, so the fixed corners must be that big.
    let reach = (radius * 1.52866483).rounded(.up)
    let image = NSImage(size: NSSize(width: reach * 2 + 2, height: reach * 2 + 2), flipped: false) { rect in
        NSColor.black.setFill()
        continuousRoundedRect(rect, radius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: reach, left: reach, bottom: reach, right: reach)
    image.resizingMode = .stretch
    return image
}
