import AppKit
import Common

struct ShortcutCheatSheetSection: Equatable {
    struct Row: Equatable {
        let keys: String
        let action: String
    }
    let title: String
    let rows: [Row]
}

/// The mode's shortcuts grouped by what they do, keys in macOS notation (⌃⌥⇧⌘).
@MainActor
func shortcutCheatSheetSections(_ mode: Mode?) -> [ShortcutCheatSheetSection] {
    guard let mode else { return [] }
    let groups: [(String, Set<CmdKind>)] = [
        ("Focus", [.focus, .focusBackAndForth, .focusMonitor, .scrollingFocus]),
        ("Move", [.move, .swap, .joinWith, .scrollingMove, .moveNodeToWorkspace, .moveNodeToMonitor, .moveWorkspaceToMonitor]),
        ("Columns", [.scrollingWidth, .scrollingWidthPixels, .resize, .balanceSizes, .scrollingCenter, .scrollingPin,
                     .scrollingPan, .layout, .fullscreen, .macosNativeFullscreen, .macosNativeMinimize, .flattenWorkspaceTree]),
        ("Spaces", [.workspace, .workspaceBackAndForth]),
    ]
    var rows: [String: [(order: String, row: ShortcutCheatSheetSection.Row)]] = [:]
    let bindings = mode.bindings.values.map { ($0.descriptionWithKeyNotation, $0.modifiers, $0.commands) }
    for (notation, modifiers, commands) in bindings where !commands.isEmpty {
        let kind = type(of: commands[0].args).info.kind
        let title = groups.first { $0.1.contains(kind) }?.0 ?? "Other"
        let action = commands.map { $0.args.description }.joined(separator: "; ")
        // Same action family together, then by key.
        rows[title, default: []].append((action + notation, .init(keys: shortcutKeySymbols(notation, modifiers), action: action)))
    }
    return (groups.map(\.0) + ["Other"]).compactMap { title in
        rows[title].map { ShortcutCheatSheetSection(title: title, rows: $0.sorted { $0.order < $1.order }.map(\.row)) }
    }
}

/// `ctrl-alt-shift-h` as `⌃⌥⇧H`, in the order macOS menus use.
func shortcutKeySymbols(_ notation: String, _ modifiers: NSEvent.ModifierFlags) -> String {
    let key = notation.split(separator: "-").last.map(String.init) ?? notation
    let names = ["slash": "/", "backslash": "\\", "comma": ",", "period": ".", "semicolon": ";", "quote": "'",
                 "minus": "−", "equal": "=", "leftSquareBracket": "[", "rightSquareBracket": "]", "backtick": "`",
                 "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "↩", "tab": "⇥", "space": "Space",
                 "esc": "⎋", "backspace": "⌫"]
    var symbols = ""
    if modifiers.contains(.control) { symbols += "⌃" }
    if modifiers.contains(.option) { symbols += "⌥" }
    if modifiers.contains(.shift) { symbols += "⇧" }
    if modifiers.contains(.command) { symbols += "⌘" }
    return symbols + (names[key] ?? key.uppercased())
}

@MainActor
final class ShortcutCheatSheet {
    static let shared = ShortcutCheatSheet()
    private var panel: NSPanel?
    var isShown: Bool { panel?.isVisible == true }

    func show(_ sections: [ShortcutCheatSheetSection], on monitor: Monitor) {
        let screens = NSScreen.screens
        let index = monitor.monitorAppKitNsScreenScreensId - 1
        let screen = screens.indices.contains(index) ? screens[index] : NSScreen.main ?? screens[0]
        let view = ShortcutCheatSheetView(sections: sections, maximumWidth: min(1040, screen.visibleFrame.width - 80))
        view.dismiss = { [weak self] in self?.dismiss() }
        let size = view.frame.size
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        dismiss() // Never two at once.
        let panel = ShortcutCheatSheetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                                          backing: .buffered, defer: false)
        self.panel = panel
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrame(frame, display: false)
        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.maskImage = roundedBlurMask(radius: overlayPanelCornerRadius)
        effect.layer?.cornerRadius = overlayPanelCornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        // Text-heavy: a mostly solid backdrop keeps it readable over busy windows.
        effect.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.82).cgColor
        effect.addSubview(view)
        panel.contentView = effect
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    /// Closes and frees the panel: its window memory is about 13 MB, for a sheet that
    /// is rarely open.
    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    func refreshColors() {
        guard isShown else { return }
        panel?.contentView?.subviews.compactMap { $0 as? ShortcutCheatSheetView }.forEach { $0.needsDisplay = true }
    }
}

@MainActor
private final class ShortcutCheatSheetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        ShortcutCheatSheet.shared.dismiss() // Clicking elsewhere closes it.
    }
}

/// Sections flow top to bottom through as many columns as fit, like a printed sheet.
@MainActor
final class ShortcutCheatSheetView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var dismiss: (() -> Void)?
    private let sections: [ShortcutCheatSheetSection]
    private(set) var columns: [[ShortcutCheatSheetSection]] = []
    private static let keysWidth: CGFloat = 76
    private static let columnWidth: CGFloat = 300
    private static let rowHeight: CGFloat = 22
    private static let headingHeight: CGFloat = 30
    private static let padding: CGFloat = 24
    private var keysWidth: CGFloat { Self.keysWidth }
    private var columnWidth: CGFloat { Self.columnWidth }
    private var rowHeight: CGFloat { Self.rowHeight }
    private var headingHeight: CGFloat { Self.headingHeight }
    private var padding: CGFloat { Self.padding }

    init(sections: [ShortcutCheatSheetSection], maximumWidth: CGFloat) {
        self.sections = sections
        let (padding, columnWidth, rowHeight, headingHeight) = (Self.padding, Self.columnWidth, Self.rowHeight, Self.headingHeight)
        let columnCount = max(1, min(3, Int((maximumWidth - padding * 2 + 24) / (columnWidth + 24))))
        let total = sections.reduce(CGFloat(0)) { $0 + headingHeight + CGFloat($1.rows.count) * rowHeight }
        // Fill each column up to an even share before starting the next; a section never splits.
        let share = total / CGFloat(columnCount)
        var columns: [[ShortcutCheatSheetSection]] = [[]]
        var height: CGFloat = 0
        for section in sections {
            let extent = headingHeight + CGFloat(section.rows.count) * rowHeight
            if height > 0, height + extent / 2 > share, columns.count < columnCount { columns.append([]); height = 0 }
            columns[columns.count - 1].append(section)
            height += extent
        }
        self.columns = columns
        let tallest = columns.map { $0.reduce(CGFloat(0)) { $0 + headingHeight + CGFloat($1.rows.count) * rowHeight } }.max() ?? 0
        let width = padding * 2 + CGFloat(columns.count) * columnWidth + CGFloat(columns.count - 1) * 24
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: padding + 34 + tallest + padding + 18))
        setAccessibilityRole(.list)
        setAccessibilityLabel("Keyboard shortcuts")
    }
    required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) { dismiss?() }
    override func mouseDown(with event: NSEvent) { dismiss?() }

    override func draw(_ dirtyRect: NSRect) {
        let accent = winMuxEmphasisColor
        draw("Keyboard shortcuts", in: CGRect(x: padding, y: padding - 4, width: bounds.width / 2, height: 22),
             font: .systemFont(ofSize: 15, weight: .semibold), color: accent)
        draw("Press any key to close", in: CGRect(x: bounds.width / 2, y: padding - 1, width: bounds.width / 2 - padding, height: 16),
             font: .systemFont(ofSize: 11), color: .secondaryLabelColor, alignment: .right)
        for (index, column) in columns.enumerated() {
            let x = padding + CGFloat(index) * (columnWidth + 24)
            var y = padding + 34
            for section in column {
                draw(section.title.uppercased(), in: CGRect(x: x, y: y + 8, width: columnWidth, height: 14),
                     font: .systemFont(ofSize: 10, weight: .semibold), color: accent)
                y += headingHeight
                for row in section.rows {
                    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
                    let keyWidth = min(keysWidth - 6, (row.keys as NSString).size(withAttributes: [.font: font]).width + 12)
                    let pill = CGRect(x: x + keysWidth - 6 - keyWidth, y: y + 2, width: keyWidth, height: rowHeight - 5)
                    accent.withAlphaComponent(0.15).setFill()
                    NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
                    draw(row.keys, in: pill.insetBy(dx: 6, dy: 1.5), font: font, color: accent, alignment: .center)
                    draw(row.action, in: CGRect(x: x + keysWidth + 4, y: y + 3.5, width: columnWidth - keysWidth - 4, height: 15),
                         font: .systemFont(ofSize: 11.5), color: .labelColor)
                    y += rowHeight
                }
            }
        }
    }

    private func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
}
