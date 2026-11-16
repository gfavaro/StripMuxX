import AppKit

/// The accent WinMuxX draws focus and selection in: borders set to `accent`, tab pills, the hover
/// bar, the workspace overview and mode indicators. Root `accent-color` sets it, so a theme can
/// match it exactly; otherwise it is the system accent, with blue for Graphite, which has no hue.
@MainActor
var winMuxAccentColor: NSColor {
    if let hex = config.accentColor, let value = UInt32(hex.dropFirst(), radix: 16) {
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    return NSColor.currentControlTint == .graphiteControlTint ? .systemBlue : .controlAccentColor
}

    
/// The shared emphasis palette used by WinMuxX borders and StripMuxX overlays.
/// Respect the border's configured active color (including its alpha); the
/// `accent` option resolves the same custom/system accent as WinMuxX.
@MainActor
var winMuxEmphasisColor: NSColor {
    let rgba = windowBorderRGBA(config.windowBorders.activeColor)
    return NSColor(srgbRed: CGFloat((rgba >> 24) & 255) / 255,
                   green: CGFloat((rgba >> 16) & 255) / 255,
                   blue: CGFloat((rgba >> 8) & 255) / 255,
                   alpha: CGFloat(rgba & 255) / 255)
}
