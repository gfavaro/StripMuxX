import AppKit
import Common

struct ScrollingMinimapTile: Equatable {
    let id: ObjectIdentifier
    let title: String
    let applications: [Int32]
    let count: Int
    /// The edge a pinned column sits at; it stays outside the strip.
    var pinned: ScrollingPinCmdArgs.Side? = nil
    /// A free-size column keeps its own window size; drawn with a dashed edge.
    var freeSize = false
    /// Where the window sits vertically in the strip, as fractions of its height: a window that
    /// keeps its own height or is free-size is not drawn filling the column.
    var vertical: ClosedRange<CGFloat> = 0...1
}

/// Height the floating row adds to the minimap when the desktop has floating windows.
let scrollingMinimapFloatingRowHeight: CGFloat = 32
let scrollingMinimapDesktopRowHeight: CGFloat = 32

/// One desktop button: its number, and whether it is the desktop this minimap shows.
struct ScrollingMinimapDesktop: Equatable {
    let number: Int
    let isCurrent: Bool
}

/// The desktops the minimap offers: those of the display `current` is on, numbered as everywhere
/// else. A display with one desktop has nothing to switch to, so it gets no row.
@MainActor
func scrollingMinimapDesktops(_ desktops: [(number: Int, workspace: Workspace)], showing current: Workspace) -> [ScrollingMinimapDesktop] {
    let display = current.workspaceMonitor.rect.topLeftCorner
    let siblings = desktops.filter { $0.workspace.workspaceMonitor.rect.topLeftCorner == display }
    guard siblings.count > 1 else { return [] }
    return siblings.map { ScrollingMinimapDesktop(number: $0.number, isCurrent: $0.workspace === current) }
}

/// Insertion index relative to tiles other than the tile currently dragged.
/// Uses the same rule for the visual preview and for the committed reorder.
func scrollingMinimapInsertionIndex(_ draggedMidX: CGFloat, otherMidpoints: [CGFloat]) -> Int {
    otherMidpoints.filter { $0 < draggedMidX }.count
}

@MainActor
final class ScrollingMinimapView: NSView {
    override var isFlipped: Bool { true }
    var selected: ((ObjectIdentifier) -> Void)?
    /// A tile dragged to a new place on the strip: its group, and the destination index.
    var reordered: ((ObjectIdentifier, Int) -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var dismissRequested: (() -> Void)?
    /// A floating window's chip clicked: its window ID.
    var floatingSelected: ((UInt32) -> Void)?
    var desktopSelected: ((Int) -> Void)?
    private var floatingChips: [ScrollingMinimapFloatingChip] = []
    private var desktopChips: [ScrollingMinimapDesktopChip] = []
    private var desktopLabelVisible = false
    private var tracking: NSTrackingArea?
    private var buttons: [ScrollingMinimapButton] = []
    private var pinnedButton: ScrollingMinimapButton?
    private let scrollView = NSScrollView()
    private let tileCanvas = ScrollingMinimapTileCanvas()
    private let viewport = ScrollingMinimapViewport()
    private var geometry: ScrollingMinimapGeometry?
    private var scrollObserver: NSObjectProtocol?
    private var keyboardSelectedID: ObjectIdentifier?
    private var focusedIndex = 0
    private var keyboardNavigation = false
    private var hovered = false
    private var previousOffset: CGFloat?
    private var previousViewportMidX: CGFloat?
    private let dropIndicator = NSView()
    private var heading = ""
    private var subheading = ""
    private var focusedTitle = ""
    private var columnPosition = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        scrollView.drawsBackground = false
        // The accent frame shows the position; no scroller or position bar.
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tileCanvas
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateViewportFrame() }
            }
        addSubview(scrollView)
        addSubview(viewport)
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.backgroundColor = winMuxEmphasisColor.cgColor
        dropIndicator.layer?.cornerRadius = 2
        dropIndicator.isHidden = true
        dropIndicator.setAccessibilityElement(false)
        addSubview(dropIndicator)
        tileCanvas.activate = { [weak self] index in self?.activateTile(at: index) }
        tileCanvas.dismiss = { [weak self] in self?.dismissRequested?() }
        tileCanvas.selectionChanged = { [weak self] index in self?.updateKeyboardSelection(index) }
    }
    required init?(coder: NSCoder) { nil }

    isolated deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    func update(workspaceName: String, models: [ScrollingMinimapTile], pinned: ScrollingMinimapTile? = nil,
                floating: [ScrollingMinimapFloatingWindow] = [], desktops: [ScrollingMinimapDesktop] = [],
                icons: [Int32: NSImage], metrics: ScrollingWorkspaceMetrics, offset: CGFloat, focused: ObjectIdentifier?) {
        heading = workspaceName
        subheading = "\(models.count) \(models.count == 1 ? "column" : "columns")" +
            (floating.isEmpty ? "" : " · \(floating.count) floating") +
            (pinned.map { " · \($0.title) pinned \($0.pinned == .right ? "right" : "left")" } ?? "")
        focusedTitle = (models + (pinned.map { [$0] } ?? [])).first { $0.id == focused }?.title
            ?? floating.first { $0.focused }?.title ?? "Click a column to reveal it"
        let activeIndex = models.firstIndex { $0.id == focused }
        columnPosition = activeIndex.map { "\($0 + 1) of \(models.count)" } ?? ""
        updateFloatingChips(floating, icons: icons)
        updateDesktopChips(desktops)
        let rowHeight = scrollingMinimapRowHeight(metrics: metrics)
        // A pinned column keeps its edge here too, beside the strip rather than on it.
        let pinnedWidth: CGFloat = pinned == nil ? 0 : min(max(rowHeight * 0.75, 32), 96)
        let pinnedOnLeft = pinned?.pinned != .right
        let stripX: CGFloat = 16 + (pinnedOnLeft && pinned != nil ? pinnedWidth + 8 : 0)
        let scrollFrame = CGRect(x: stripX, y: 29, width: max(bounds.width - 32 - (pinned == nil ? 0 : pinnedWidth + 8), 1),
                                 height: rowHeight + 6)
        scrollView.frame = scrollFrame
        updatePinnedButton(pinned, icons: icons, focused: focused, frame: CGRect(
            x: pinnedOnLeft ? 16 : bounds.width - 16 - pinnedWidth, y: 29, width: pinnedWidth, height: rowHeight))
        let contentWidth = scrollingMinimapContentWidth(metrics: metrics, visibleWidth: scrollFrame.width)
        tileCanvas.frame = CGRect(x: 0, y: 0, width: contentWidth, height: rowHeight)
        focusedIndex = models.firstIndex { $0.id == focused } ?? 0
        let selectedIndex = (keyboardNavigation ? keyboardSelectedID : nil).flatMap { id in models.firstIndex { $0.id == id } }
            ?? models.firstIndex { $0.id == focused } ?? 0
        tileCanvas.selectedIndex = selectedIndex
        keyboardSelectedID = models.indices.contains(selectedIndex) ? models[selectedIndex].id : nil
        if buttons.map(\.model.id) != models.map(\.id) {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = models.map { model in
                let button = ScrollingMinimapButton(model: model)
                button.target = self
                button.action = #selector(selectTile(_:))
                button.dropped = { [weak self] button, midX in self?.dropTile(button, at: midX) }
                button.dragPreview = { [weak self] button, midX in self?.showDropPreview(for: button, at: midX) }
                button.dragEnded = { [weak self] in self?.dropIndicator.isHidden = true }
                button.autoScroll = { [weak self] location in self?.scrollDuringTileDrag(windowX: location) ?? 0 }
                tileCanvas.addSubview(button)
                return button
            }
        }
        let map = ScrollingMinimapGeometry(metrics: metrics, offset: offset,
            bounds: CGRect(x: 0, y: 0, width: contentWidth, height: rowHeight))
        geometry = map
        for (index, button) in buttons.enumerated() {
            button.configure(models[index], icons: icons, focused: models[index].id == focused,
                             keyboardSelected: keyboardNavigation && index == selectedIndex)
            let tile = map.tiles[index]
            let target = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height)
            if button.frame != target { button.frame = target }
        }
        // The minimap's scale can change when columns are inserted/resized even
        // if the workspace offset stays the same. Track mapped geometry too.
        let viewportChanged = previousViewportMidX.map { abs($0 - map.viewport.midX) > 0.5 } ?? true
        if (previousOffset != offset || viewportChanged), !hovered, !keyboardNavigation {
            let visibleWidth = scrollView.contentView.bounds.width
            let x = min(max(map.viewport.midX - visibleWidth / 2, 0), max(contentWidth - visibleWidth, 0))
            scrollView.contentView.scroll(to: CGPoint(x: x, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if keyboardNavigation, buttons.indices.contains(selectedIndex) {
            // Asynchronous title/model updates must not strand the keyboard
            // selection outside the scroll view's visible portion.
            tileCanvas.scrollToVisible(buttons[selectedIndex].frame)
        }
        previousOffset = offset
        previousViewportMidX = map.viewport.midX
        updateViewportFrame()
        dropIndicator.layer?.backgroundColor = winMuxEmphasisColor.cgColor
        viewport.needsDisplay = true
        needsDisplay = true
    }

    private func updateFloatingChips(_ floating: [ScrollingMinimapFloatingWindow], icons: [Int32: NSImage]) {
        if floatingChips.map(\.model.windowId) != floating.map(\.windowId) {
            floatingChips.forEach { $0.removeFromSuperview() }
            floatingChips = floating.map { model in
                let chip = ScrollingMinimapFloatingChip(model: model)
                chip.target = self
                chip.action = #selector(selectFloating(_:))
                addSubview(chip)
                return chip
            }
        }
        // One row above the footer, left to right after its label; chips that do not fit are hidden.
        var x: CGFloat = 80
        let y = bounds.height - 23 - scrollingMinimapFloatingRowHeight + 2
        for (chip, model) in zip(floatingChips, floating) {
            chip.configure(model, icon: icons[model.pid])
            let width = min(170, max(84, chip.preferredWidth))
            chip.isHidden = x + width > bounds.width - 16
            let target = CGRect(x: x, y: y, width: width, height: 24)
            if chip.frame != target { chip.frame = target }
            x += width + 6
        }
        floatingLabelVisible = !floating.isEmpty
    }
    private var floatingLabelVisible = false

    /// A row above the floating windows' (or the footer when there are none): one button per desktop of this display.
    private func updateDesktopChips(_ desktops: [ScrollingMinimapDesktop]) {
        if desktopChips.map(\.model.number) != desktops.map(\.number) {
            desktopChips.forEach { $0.removeFromSuperview() }
            desktopChips = desktops.map { model in
                let chip = ScrollingMinimapDesktopChip(model: model)
                chip.target = self
                chip.action = #selector(selectDesktop(_:))
                addSubview(chip)
                return chip
            }
        }
        var x: CGFloat = 80
        let y = desktopRowTop + 2
        for (chip, model) in zip(desktopChips, desktops) {
            chip.configure(model)
            chip.isHidden = x + 30 > bounds.width - 16
            let target = CGRect(x: x, y: y, width: 30, height: 24)
            if chip.frame != target { chip.frame = target }
            x += 36
        }
        desktopLabelVisible = !desktops.isEmpty
    }

    /// Top of the desktops row: it sits above the floating windows' row when there is one.
    private var desktopRowTop: CGFloat {
        bounds.height - 23 - (floatingLabelVisible ? scrollingMinimapFloatingRowHeight : 0) - scrollingMinimapDesktopRowHeight
    }

    @objc private func selectDesktop(_ sender: ScrollingMinimapDesktopChip) {
        desktopSelected?(sender.model.number)
    }

    @objc private func selectFloating(_ sender: ScrollingMinimapFloatingChip) {
        floatingSelected?(sender.model.windowId)
    }

    private func updatePinnedButton(_ model: ScrollingMinimapTile?, icons: [Int32: NSImage], focused: ObjectIdentifier?, frame: CGRect) {
        guard let model else { pinnedButton?.removeFromSuperview(); pinnedButton = nil; return }
        let button = pinnedButton ?? {
            let button = ScrollingMinimapButton(model: model)
            button.target = self
            button.action = #selector(selectPinned(_:))
            addSubview(button)
            pinnedButton = button
            return button
        }()
        button.configure(model, icons: icons, focused: model.id == focused, keyboardSelected: false)
        if button.frame != frame { button.frame = frame }
    }

    /// While a tile is being dragged, move the scroll canvas near its edges.
    /// Returns the document-coordinate shift so the tile continues following
    /// the pointer rather than jumping when the viewport scrolls.
    private func scrollDuringTileDrag(windowX: CGFloat) -> CGFloat {
        let local = convert(CGPoint(x: windowX, y: 0), from: nil)
        let clip = scrollView.contentView
        let previous = clip.bounds.minX
        let delta = scrollingMinimapEdgeScrollDelta(pointerX: local.x - scrollView.frame.minX,
            viewportWidth: clip.bounds.width, contentOffset: previous,
            contentWidth: tileCanvas.frame.width)
        guard delta != 0 else { return 0 }
        clip.scroll(to: CGPoint(x: previous + delta, y: clip.bounds.minY))
        scrollView.reflectScrolledClipView(clip)
        updateViewportFrame()
        return clip.bounds.minX - previous
    }

    @objc private func selectPinned(_ sender: ScrollingMinimapButton) { selected?(sender.model.id) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(next)
        tracking = next
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; hoverChanged?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// The place among the other tiles whose centre the dropped tile passed.
    private func dropTile(_ dropped: ScrollingMinimapButton, at midX: CGFloat) {
        dropIndicator.isHidden = true
        let others = buttons.filter { $0 !== dropped }
        let index = scrollingMinimapInsertionIndex(midX, otherMidpoints: others.map { $0.frame.midX })
        guard let current = buttons.firstIndex(where: { $0 === dropped }) else { return }
        if index != current { reordered?(dropped.model.id, index) }
        else { dropped.frame.origin.x = geometry.map { $0.tiles[current].minX } ?? dropped.frame.origin.x }
    }

    /// Shows the insertion slot in viewport coordinates, without moving any
    /// managed window or changing the model before the mouse is released.
    private func showDropPreview(for dropped: ScrollingMinimapButton, at midX: CGFloat) {
        let others = buttons.filter { $0 !== dropped }
        guard !others.isEmpty else { dropIndicator.isHidden = true; return }
        let index = scrollingMinimapInsertionIndex(midX, otherMidpoints: others.map { $0.frame.midX })
        let targetX: CGFloat
        if index == 0 { targetX = others[0].frame.minX }
        else if index == others.count { targetX = others[others.count - 1].frame.maxX }
        else { targetX = (others[index - 1].frame.maxX + others[index].frame.minX) / 2 }
        let x = scrollView.frame.minX + targetX - scrollView.contentView.bounds.minX
        guard x >= scrollView.frame.minX - 2, x <= scrollView.frame.maxX + 2 else {
            dropIndicator.isHidden = true
            return
        }
        let target = CGRect(x: x - 2, y: scrollView.frame.minY + 2,
                            width: 4, height: max(scrollView.frame.height - 4, 0))
        if dropIndicator.frame != target { dropIndicator.frame = target }
        dropIndicator.isHidden = false
    }

    func beginKeyboardNavigation() {
        keyboardNavigation = true
        tileCanvas.selectedIndex = focusedIndex
        updateKeyboardSelection(focusedIndex)
        window?.makeFirstResponder(self)
    }
    func endKeyboardNavigation() {
        keyboardNavigation = false
        keyboardSelectedID = nil
        for button in buttons { button.setKeyboardSelected(false) }
    }
    func resetPresentation() {
        endKeyboardNavigation()
        hovered = false
        previousOffset = nil
        previousViewportMidX = nil
        dropIndicator.isHidden = true
    }
    override func keyDown(with event: NSEvent) {
        guard !buttons.isEmpty else { return }
        switch event.keyCode {
            case 123: tileCanvas.moveSelection(by: -1)
            case 124: tileCanvas.moveSelection(by: 1)
            case 36, 76, 49: activateTile(at: tileCanvas.selectedIndex)
            case 53: dismissRequested?()
            default: super.keyDown(with: event)
        }
    }
    private func activateTile(at index: Int) {
        guard buttons.indices.contains(index) else { return }
        selected?(buttons[index].model.id)
    }
    private func updateKeyboardSelection(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        keyboardSelectedID = buttons[index].model.id
        for (i, button) in buttons.enumerated() {
            button.setKeyboardSelected(i == index)
        }
    }
    private func updateViewportFrame() {
        guard let geometry else { return }
        let scrollFrame = scrollView.frame
        viewport.frame = CGRect(x: scrollFrame.minX + geometry.viewport.minX - scrollView.contentView.bounds.minX - 2,
                                y: scrollFrame.minY + geometry.viewport.minY - scrollView.contentView.bounds.minY - 2,
                                width: geometry.viewport.width + 4, height: geometry.viewport.height + 4)
        viewport.needsDisplay = true
    }
    @objc private func selectTile(_ sender: ScrollingMinimapButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        tileCanvas.selectedIndex = index
        selected?(sender.model.id)
    }

    override func draw(_ dirtyRect: NSRect) {
        let headingFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let headingWidth = min((heading as NSString).size(withAttributes: [.font: headingFont]).width + 2, bounds.width * 0.5)
        drawMinimapText(heading, in: CGRect(x: 16, y: 8, width: headingWidth, height: 17), font: headingFont, color: .labelColor)
        drawMinimapText(subheading, in: CGRect(x: 16 + headingWidth + 8, y: 9.5, width: bounds.width - headingWidth - 130, height: 15),
                        font: .systemFont(ofSize: 10.5), color: .secondaryLabelColor)
        if !columnPosition.isEmpty {
            // The focused column's place, in a pill at the top right.
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            let width = (columnPosition as NSString).size(withAttributes: [.font: font]).width + 16
            let pill = CGRect(x: bounds.width - 16 - width, y: 7, width: width, height: 18)
            winMuxEmphasisColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            drawMinimapText(columnPosition, in: pill.insetBy(dx: 8, dy: 2.5), font: font,
                            color: winMuxEmphasisColor, alignment: .center)
        }
        if desktopLabelVisible {
            drawMinimapText("Desktops", in: CGRect(x: 16, y: desktopRowTop + 7, width: 60, height: 14),
                            font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        }
        if floatingLabelVisible {
            drawMinimapText("Floating", in: CGRect(x: 16, y: bounds.height - 23 - scrollingMinimapFloatingRowHeight + 7,
                            width: 60, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        }
        // A compact panel keeps only the focused title; the hint needs a wide one.
        let showsHint = bounds.width >= 520
        drawMinimapText(focusedTitle,
                        in: CGRect(x: 16, y: bounds.height - 23, width: showsHint ? bounds.width * 0.55 : bounds.width - 32, height: 16),
                        font: .systemFont(ofSize: 10, weight: .medium), color: .labelColor)
        guard showsHint else { return }
        let navigationHint = config.scrolling.threeFingerSwipe && config.scrolling.gestureEnabled
            ? "Click to reveal · drag to reorder · three-finger swipe"
            : config.scrolling.gestureEnabled ? "Click to reveal · drag to reorder · ⌥ two-finger scroll"
            : "Click to reveal · drag to reorder · arrow keys"
        drawMinimapText(navigationHint, in: CGRect(x: bounds.width * 0.58, y: bounds.height - 23,
                        width: bounds.width * 0.42 - 16, height: 16), font: .systemFont(ofSize: 10),
                        color: .secondaryLabelColor, alignment: .right)
    }
}

@MainActor
private final class ScrollingMinimapTileCanvas: NSView {
    override var isFlipped: Bool { true }
    var activate: ((Int) -> Void)?
    var dismiss: (() -> Void)?
    var selectionChanged: ((Int) -> Void)?
    var selectedIndex = 0
    override var acceptsFirstResponder: Bool { true }
    func moveSelection(by delta: Int) {
        let candidates = subviews.filterIsInstance(of: ScrollingMinimapButton.self)
        guard !candidates.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), candidates.count - 1)
        scrollToVisible(candidates[selectedIndex].frame)
        selectionChanged?(selectedIndex)
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 123: moveSelection(by: -1)
            case 124: moveSelection(by: 1)
            case 36, 76, 49: activate?(selectedIndex)
            case 53: dismiss?()
            default: super.keyDown(with: event)
        }
    }
}

@MainActor
final class ScrollingMinimapButton: NSButton {
    override var isFlipped: Bool { true }
    private(set) var model: ScrollingMinimapTile
    private(set) var icons: [NSImage] = []
    private var focused = false
    private var keyboardSelected = false
    private var configured = false

    /// Called on release after a horizontal drag, with the tile's centre in the canvas.
    var dropped: ((ScrollingMinimapButton, CGFloat) -> Void)?
    /// Invoked only during a real pointer drag; returns the canvas scroll distance.
    var autoScroll: ((CGFloat) -> CGFloat)?
    var dragPreview: ((ScrollingMinimapButton, CGFloat) -> Void)?
    var dragEnded: (() -> Void)?

    /// A click activates the tile; a drag past a few points moves it to reorder columns.
    override func mouseDown(with event: NSEvent) {
        guard let window, dropped != nil else { return super.mouseDown(with: event) }
        let start = event.locationInWindow
        let origin = frame.origin.x
        var dragging = false
        var scrollDisplacement: CGFloat = 0
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let delta = next.locationInWindow.x - start.x
            if next.type == .leftMouseUp {
                dragEnded?()
                if dragging { dropped?(self, frame.midX) } else { _ = sendAction(action, to: target) }
                return
            }
            if !dragging, abs(delta) > 4 { dragging = true; superview?.addSubview(self) } // Drawn above its neighbours.
            if dragging {
                scrollDisplacement += autoScroll?(next.locationInWindow.x) ?? 0
                frame.origin.x = origin + delta + scrollDisplacement
                dragPreview?(self, frame.midX)
            }
        }
        dragEnded?()
    }

    init(model: ScrollingMinimapTile) {
        self.model = model
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .exterior
        setAccessibilityHelp("Focus and reveal this workspace group")
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ model: ScrollingMinimapTile, icons: [Int32: NSImage], focused: Bool, keyboardSelected: Bool) {
        let updatedIcons = model.applications.prefix(3).compactMap { icons[$0] }
        let iconsChanged = self.icons.count != updatedIcons.count ||
            !zip(self.icons, updatedIcons).allSatisfy { $0 === $1 }
        guard !configured || self.model != model || self.focused != focused ||
              self.keyboardSelected != keyboardSelected || iconsChanged else { return }
        configured = true
        self.model = model
        self.icons = updatedIcons
        self.focused = focused
        self.keyboardSelected = keyboardSelected
        let count = (model.count > 1 ? ", \(model.count) windows" : "") +
            (model.pinned.map { ", pinned \($0 == .right ? "right" : "left")" } ?? "")
        toolTip = model.title + count
        setAccessibilityLabel(model.title + count)
        setAccessibilityValue(focused ? "Focused group" : "")
        needsDisplay = true
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard keyboardSelected != selected else { return }
        keyboardSelected = selected
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // A miniature window: a card with a title bar, the app's icon and its title.
        let full = bounds.insetBy(dx: 2, dy: 2)
        let tile = CGRect(x: full.minX, y: full.minY + full.height * model.vertical.lowerBound, width: full.width,
                          height: full.height * (model.vertical.upperBound - model.vertical.lowerBound))
        let path = continuousRoundedRect(tile, radius: scrollingMinimapTileRadius)
        let accent = winMuxEmphasisColor
        (focused ? accent.withAlphaComponent(0.22)
            : isHighlighted ? accent.withAlphaComponent(0.14)
            : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
        path.fill()
        if tile.width >= 24 {
            // Title bar, divided once per window of a stack.
            let bar = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 7)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            (focused ? accent.withAlphaComponent(0.35) : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
            bar.fill()
            if model.count > 1 {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                let rows = min(model.count, 4)
                for row in 1 ..< rows {
                    let y = bar.maxY + (tile.height - bar.height) * CGFloat(row) / CGFloat(rows)
                    CGRect(x: tile.minX + 6, y: y - 0.5, width: tile.width - 12, height: 1).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        (focused ? accent : NSColor.labelColor.withAlphaComponent(increaseContrast ? 0.5 : 0.16)).setStroke()
        path.lineWidth = focused ? 2 : increaseContrast ? 1.5 : 1
        if model.freeSize { path.setLineDash([4, 3], count: 2, phase: 0) }
        path.stroke()
        if keyboardSelected {
            let ring = continuousRoundedRect(tile.insetBy(dx: -1.5, dy: -1.5), radius: scrollingMinimapTileRadius + 1.5)
            accent.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
        guard bounds.width >= 18 else { return }
        let showsTitle = bounds.width >= 56 && tile.height >= 44
        let side: CGFloat = bounds.width >= 56 ? 20 : 16
        let count = bounds.width >= 80 ? icons.count : min(icons.count, 1)
        let iconsWidth = CGFloat(count) * side + CGFloat(max(count - 1, 0)) * 3
        let iconY = showsTitle ? max(tile.minY + 12, tile.midY - side - 2) : tile.midY - side / 2 + 3
        for (index, icon) in icons.prefix(count).enumerated() {
            let x = (bounds.width - iconsWidth) / 2 + CGFloat(index) * (side + 3)
            let image: NSImage
            if icon.isTemplate {
                image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
                    icon.draw(in: rect)
                    NSColor.labelColor.setFill()
                    rect.fill(using: .sourceIn)
                    return true
                }
            } else { image = icon }
            image.draw(in: CGRect(x: x, y: iconY, width: side, height: side), from: .zero, operation: .sourceOver,
                      fraction: focused ? 1 : 0.9, respectFlipped: true, hints: nil)
        }
        if model.pinned != nil, let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") {
            let badge = NSImage(size: CGSize(width: 10, height: 10), flipped: false) { rect in
                pin.draw(in: rect)
                accent.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            badge.draw(in: CGRect(x: bounds.width - 15, y: tile.minY + 9, width: 10, height: 10), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        if model.count > 1, bounds.width >= 40 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            drawMinimapText("\(model.count)", in: CGRect(x: tile.minX + 6, y: tile.minY + 9, width: 20, height: 12),
                            font: font, color: .secondaryLabelColor)
        }
        if showsTitle {
            drawMinimapText(model.title, in: CGRect(x: 7, y: iconY + side + 5, width: bounds.width - 14, height: 14),
                            font: .systemFont(ofSize: 10, weight: focused ? .semibold : .regular),
                            color: focused ? .labelColor : .secondaryLabelColor, alignment: .center)
        }
    }
}

/// A floating window, listed under the strip so it can be found.
struct ScrollingMinimapFloatingWindow: Equatable {
    let windowId: UInt32
    let pid: Int32
    let title: String
    var focused = false
}

/// A desktop's number as a small button; the desktop the minimap shows is drawn in the accent.
@MainActor
final class ScrollingMinimapDesktopChip: NSButton {
    override var isFlipped: Bool { true }
    private(set) var model: ScrollingMinimapDesktop

    init(model: ScrollingMinimapDesktop) {
        self.model = model
        super.init(frame: .zero)
        title = ""
        isBordered = false
        configureAccessibility()
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ model: ScrollingMinimapDesktop) {
        guard self.model != model else { return }
        self.model = model
        configureAccessibility()
        needsDisplay = true
    }

    private func configureAccessibility() {
        toolTip = nativeDesktopDisplayName(model.number)
        setAccessibilityLabel(nativeDesktopDisplayName(model.number))
        setAccessibilityValue(model.isCurrent ? "Current" : "")
        setAccessibilityHelp("Switch to this desktop")
    }

    override func draw(_ dirtyRect: NSRect) {
        let chip = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (model.isCurrent ? winMuxEmphasisColor.withAlphaComponent(0.22)
            : isHighlighted ? winMuxEmphasisColor.withAlphaComponent(0.14)
            : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
        chip.fill()
        (model.isCurrent ? winMuxEmphasisColor : NSColor.labelColor.withAlphaComponent(0.16)).setStroke()
        chip.lineWidth = model.isCurrent ? 1.5 : 1
        chip.stroke()
        drawMinimapText(String(model.number), in: CGRect(x: 0, y: 5, width: bounds.width, height: 14),
                        font: .monospacedDigitSystemFont(ofSize: 11, weight: model.isCurrent ? .semibold : .regular),
                        color: model.isCurrent ? winMuxEmphasisColor : .labelColor, alignment: .center)
    }
}

@MainActor
final class ScrollingMinimapFloatingChip: NSButton {
    override var isFlipped: Bool { true }
    private(set) var model: ScrollingMinimapFloatingWindow
    private var icon: NSImage?

    init(model: ScrollingMinimapFloatingWindow) {
        self.model = model
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setAccessibilityHelp("Focus this floating window")
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var preferredWidth: CGFloat {
        (model.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width + 36
    }

    func configure(_ model: ScrollingMinimapFloatingWindow, icon: NSImage?) {
        guard self.model != model || self.icon !== icon else { return }
        self.model = model
        self.icon = icon
        toolTip = model.title
        setAccessibilityLabel(model.title)
        setAccessibilityValue(model.focused ? "Focused" : "")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let chip = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (model.focused ? winMuxEmphasisColor.withAlphaComponent(0.22)
            : isHighlighted ? winMuxEmphasisColor.withAlphaComponent(0.14)
            : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
        chip.fill()
        (model.focused ? winMuxEmphasisColor : NSColor.labelColor.withAlphaComponent(0.16)).setStroke()
        chip.lineWidth = model.focused ? 1.5 : 1
        chip.stroke()
        icon?.draw(in: CGRect(x: 6, y: 4, width: 16, height: 16), from: .zero, operation: .sourceOver,
                   fraction: 1, respectFlipped: true, hints: nil)
        drawMinimapText(model.title, in: CGRect(x: 26, y: 5, width: bounds.width - 34, height: 14),
                        font: .systemFont(ofSize: 10, weight: model.focused ? .semibold : .regular), color: .labelColor)
    }
}

@MainActor
private final class ScrollingMinimapViewport: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        // The part of the strip on screen: a soft accent frame around those columns.
        let outline = continuousRoundedRect(bounds.insetBy(dx: 1, dy: 1), radius: scrollingMinimapViewportRadius)
        winMuxEmphasisColor.withAlphaComponent(0.06).setFill()
        outline.fill()
        winMuxEmphasisColor.withAlphaComponent(0.6).setStroke()
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

@MainActor
private func drawMinimapText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor,
                             alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    style.alignment = alignment
    (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
}

/// The minimap's corner radii, nested so that every edge that sits inside another follows its curve:
/// a tile inside the viewport frame inside the panel.
let scrollingMinimapPanelRadius = overlayPanelCornerRadius
let scrollingMinimapTileRadius: CGFloat = 10
let scrollingMinimapViewportRadius: CGFloat = scrollingMinimapTileRadius + 3

/// A rounded rectangle with macOS's continuous corners: the curve eases into the straight edge
/// instead of meeting it at a fixed arc, which is what system windows and controls use.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    // A continuous corner reaches 1.5287 radii along each edge, so a small rect gets a smaller radius.
    let r = min(radius, min(rect.width, rect.height) / (2 * 1.52866483))
    guard r > 0 else { return NSBezierPath(rect: rect) }
    let path = NSBezierPath()
    // Offsets are written once for the top-right corner (x along the incoming edge, measured back
    // from the corner; y inward) and turned a quarter each time to reach the others, clockwise.
    func point(_ x: CGFloat, _ y: CGFloat, corner: Int) -> CGPoint {
        switch corner {
            case 0: CGPoint(x: rect.maxX - x * r, y: rect.minY + y * r) // top right
            case 1: CGPoint(x: rect.maxX - y * r, y: rect.maxY - x * r) // bottom right
            case 2: CGPoint(x: rect.minX + x * r, y: rect.maxY - y * r) // bottom left
            default: CGPoint(x: rect.minX + y * r, y: rect.minY + x * r) // top left
        }
    }
    path.move(to: point(0, 1.52866483, corner: 3))
    for corner in 0 ..< 4 {
        path.line(to: point(1.52866483, 0, corner: corner))
        path.curve(to: point(0.63149379, 0.07491139, corner: corner),
                   controlPoint1: point(1.08849296, 0, corner: corner), controlPoint2: point(0.86840694, 0, corner: corner))
        path.curve(to: point(0.07491139, 0.63149379, corner: corner),
                   controlPoint1: point(0.37282383, 0.16906013, corner: corner), controlPoint2: point(0.16906013, 0.37282383, corner: corner))
        path.curve(to: point(0, 1.52866483, corner: corner),
                   controlPoint1: point(0, 0.86840694, corner: corner), controlPoint2: point(0, 1.08849296, corner: corner))
    }
    path.close()
    return path
}
