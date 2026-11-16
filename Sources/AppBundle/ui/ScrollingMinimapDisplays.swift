import AppKit
import Common

/// The apps with windows on a desktop, most recent first, for the minimap to show as icons: their
/// process ids and names. At most three are kept; the rest do not fit.
struct ScrollingMinimapApps: Equatable {
    let pids: [Int32]
    let names: [String]
    static let none = ScrollingMinimapApps(pids: [], names: [])
}

/// Height of the displays row: a tall arrangement (a display above another) gets room for its icons.
func scrollingMinimapDisplayRowHeight(_ displays: [ScrollingMinimapDisplay]) -> CGFloat {
    guard let first = displays.first, displays.count > 1 else { return 0 }
    let union = displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    return union.height > union.width * 0.75 ? 100 : 60
}

/// One display in the minimap's picture of how the displays are arranged.
struct ScrollingMinimapDisplay: Equatable {
    /// Position in the sorted monitor list; looked up again when the button is clicked.
    let index: Int
    let name: String
    /// The display's real frame, in the coordinates all displays share (y grows downward).
    let frame: CGRect
    /// The desktop it shows now.
    let desktop: Int?
    /// The display this minimap is drawing.
    let isShown: Bool
    /// Whether its desktop has windows: only then is there a strip to show.
    let hasWindows: Bool
    let apps: ScrollingMinimapApps
}

/// The displays as the minimap pictures them: nothing unless there are two or more.
@MainActor
func scrollingMinimapDisplays(_ monitors: [any Monitor], showing current: Workspace,
                              apps: (Workspace) -> ScrollingMinimapApps = { _ in .none }) -> [ScrollingMinimapDisplay] {
    guard monitors.count > 1 else { return [] }
    let shown = current.workspaceMonitor.rect.topLeftCorner
    return monitors.enumerated().map { index, monitor in
        let desktop = nativeActiveDesktop(on: monitor)
        return ScrollingMinimapDisplay(
            index: index, name: monitor.name,
            frame: CGRect(x: monitor.rect.topLeftX, y: monitor.rect.topLeftY, width: monitor.rect.width, height: monitor.rect.height),
            desktop: desktop.flatMap(nativeDesktopNumber(of:)), isShown: monitor.rect.topLeftCorner == shown,
            hasWindows: desktop?.mostRecentWindowRecursive != nil, apps: desktop.map(apps) ?? .none)
    }
}

/// Where each display's miniature goes in `area`: the real arrangement scaled down by one factor and
/// left-aligned, so a display to the right is drawn to the right and one above is drawn above.
func scrollingMinimapDisplayFrames(_ displays: [ScrollingMinimapDisplay], in area: CGSize) -> [CGRect] {
    guard let first = displays.first, area.width > 0, area.height > 0 else { return [] }
    let union = displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    guard union.width > 0, union.height > 0 else { return displays.map { _ in .zero } }
    let scale = min(area.width / union.width, area.height / union.height)
    let gap: CGFloat = 1.5
    return displays.map { display in
        CGRect(x: (display.frame.minX - union.minX) * scale, y: (display.frame.minY - union.minY) * scale,
               width: display.frame.width * scale, height: display.frame.height * scale).insetBy(dx: gap, dy: gap)
    }
}

/// A miniature of one display. The one the minimap draws is in the accent; a display with no windows
/// is dimmed and cannot be clicked.
@MainActor
final class ScrollingMinimapDisplayButton: NSButton {
    override var isFlipped: Bool { true }
    private(set) var model: ScrollingMinimapDisplay

    init(model: ScrollingMinimapDisplay) {
        self.model = model
        super.init(frame: .zero)
        title = ""
        isBordered = false
        configureAccessibility()
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var icons: [Int32: NSImage] = [:]

    func configure(_ model: ScrollingMinimapDisplay, icons: [Int32: NSImage]) {
        let sameIcons = model.apps.pids.allSatisfy { self.icons[$0] === icons[$0] }
        guard self.model != model || !sameIcons else { return }
        self.model = model
        self.icons = icons
        configureAccessibility()
        needsDisplay = true
    }

    private func configureAccessibility() {
        let place = model.desktop.map { nativeDesktopDisplayName($0) } ?? "no desktop"
        let apps = model.apps.names.isEmpty ? "" : " · " + model.apps.names.joined(separator: ", ")
        toolTip = model.hasWindows || model.isShown ? "\(model.name) · \(place)\(apps)" : "\(model.name) · \(place) · no windows"
        setAccessibilityLabel("Display \(model.name), \(place)")
        setAccessibilityValue(model.isShown ? "Shown" : model.hasWindows ? "" : "No windows")
        setAccessibilityHelp("Show this display's desktop")
        isEnabled = model.hasWindows && !model.isShown
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = continuousRoundedRect(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 5)
        let dim: CGFloat = model.hasWindows || model.isShown ? 1 : 0.5
        (model.isShown ? winMuxEmphasisColor.withAlphaComponent(0.22)
            : isHighlighted ? winMuxEmphasisColor.withAlphaComponent(0.14)
            : NSColor.labelColor.withAlphaComponent(0.07 * dim)).setFill()
        shape.fill()
        (model.isShown ? winMuxEmphasisColor : NSColor.labelColor.withAlphaComponent(0.16 * dim)).setStroke()
        shape.lineWidth = model.isShown ? 1.5 : 1
        shape.stroke()
        guard bounds.width >= 14, bounds.height >= 12 else { return }
        // The number on top; the apps' icons in a row under it when the miniature is tall enough for both.
        let side: CGFloat = 13
        let shown = model.apps.pids.compactMap { icons[$0] }
        let roomForIcons = bounds.height >= 34 && bounds.width >= side + 6 && !shown.isEmpty
        let numberY = roomForIcons ? 4 : bounds.midY - 7
        drawMinimapText(model.desktop.map(String.init) ?? "–", in: CGRect(x: 0, y: numberY, width: bounds.width, height: 14),
                        font: .monospacedDigitSystemFont(ofSize: 11, weight: model.isShown ? .semibold : .regular),
                        color: model.isShown ? winMuxEmphasisColor : NSColor.labelColor.withAlphaComponent(dim), alignment: .center)
        guard roomForIcons else { return }
        let fit = min(shown.count, max(Int((bounds.width - 6) / (side + 2)), 1))
        let total = CGFloat(fit) * side + CGFloat(fit - 1) * 2
        for (index, icon) in shown.prefix(fit).enumerated() {
            drawMinimapIcon(icon, in: CGRect(x: (bounds.width - total) / 2 + CGFloat(index) * (side + 2), y: bounds.height - side - 5,
                                             width: side, height: side), fraction: dim)
        }
    }
}
