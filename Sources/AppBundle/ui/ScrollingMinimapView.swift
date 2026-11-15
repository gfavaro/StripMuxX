import AppKit
import Common

struct ScrollingMinimapTile: Equatable {
    let id: ObjectIdentifier
    let title: String
    let applications: [Int32]
    let count: Int
    /// The edge a pinned column sits at; it stays outside the strip.
    var pinned: ScrollingPinCmdArgs.Side? = nil
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
    private var focusedTitle = ""
    private var columnPosition = ""
    private var positionTrack: CGRect = .zero
    private var positionThumb: CGRect = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
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
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
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
                icons: [Int32: NSImage], metrics: ScrollingWorkspaceMetrics, offset: CGFloat, focused: ObjectIdentifier?) {
        heading = "\(workspaceName) · \(models.count) \(models.count == 1 ? "group" : "groups")" +
            (pinned.map { " · \($0.title) pinned \($0.pinned == .right ? "right" : "left")" } ?? "")
        focusedTitle = (models + (pinned.map { [$0] } ?? [])).first { $0.id == focused }?.title ?? "Click a group to reveal it"
        let activeIndex = models.firstIndex { $0.id == focused }
        columnPosition = activeIndex.map { "\($0 + 1) / \(models.count)" } ?? "\(models.count) groups"
        let rowHeight = scrollingMinimapRowHeight(metrics: metrics)
        // A pinned column keeps its edge here too, beside the strip rather than on it.
        let pinnedWidth: CGFloat = pinned == nil ? 0 : min(max(rowHeight * 0.75, 32), 96)
        let pinnedOnLeft = pinned?.pinned != .right
        let stripX: CGFloat = 16 + (pinnedOnLeft && pinned != nil ? pinnedWidth + 8 : 0)
        let scrollFrame = CGRect(x: stripX, y: 29, width: max(bounds.width - 32 - (pinned == nil ? 0 : pinnedWidth + 8), 1),
                                 height: rowHeight + 6)
        scrollView.frame = scrollFrame
        // Dedicated overview bar below the tiles: its thumb shows both the
        // viewport's fractional width and its position across the entire strip.
        positionTrack = CGRect(x: scrollFrame.minX, y: scrollFrame.maxY + 8,
                               width: scrollFrame.width, height: 4)
        let range = metrics.offsetRange
        let progress = range.upperBound > range.lowerBound
            ? (metrics.clampedOffset(offset) - range.lowerBound) / (range.upperBound - range.lowerBound)
            : 0
        let proportion = min(1, metrics.areaWidth / max(metrics.totalWidth, metrics.areaWidth, 1))
        let thumbWidth = min(positionTrack.width, max(18, positionTrack.width * proportion))
        positionThumb = CGRect(x: positionTrack.minX + (positionTrack.width - thumbWidth) * min(max(progress, 0), 1),
                               y: positionTrack.minY, width: thumbWidth, height: positionTrack.height)
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
        viewport.needsDisplay = true
        needsDisplay = true
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
        drawMinimapText(heading, in: CGRect(x: 16, y: 9, width: bounds.width - 116, height: 17),
                        font: .systemFont(ofSize: 11, weight: .semibold), color: .labelColor)
        drawMinimapText(columnPosition, in: CGRect(x: bounds.width - 100, y: 9, width: 84, height: 17),
                        font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                        color: .secondaryLabelColor, alignment: .right)
        if !positionTrack.isEmpty {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: positionTrack, xRadius: 2, yRadius: 2).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: positionThumb, xRadius: 2, yRadius: 2).fill()
        }
        drawMinimapText("Selected · " + focusedTitle,
                        in: CGRect(x: 16, y: bounds.height - 23, width: bounds.width * 0.55, height: 16),
                        font: .systemFont(ofSize: 10, weight: .medium), color: .labelColor)
        let navigationHint = config.scrolling.threeFingerSwipe && config.scrolling.gestureEnabled
            ? "Click to reveal · Three-finger swipe"
            : config.scrolling.gestureEnabled ? "Click to reveal · ⌥ + two-finger scroll" : "Click to reveal · Arrow keys"
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
        let tile = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: tile, xRadius: 7, yRadius: 7)
        (focused ? NSColor.controlAccentColor.withAlphaComponent(0.36)
            : isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.24)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.75)).setFill()
        path.fill()
        (focused ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = focused ? 2.5 : NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
        path.stroke()
        if keyboardSelected {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 2.5
            ring.stroke()
        }
        guard bounds.width >= 18 else { return }
        let count = bounds.width >= 80 ? icons.count : min(icons.count, 1)
        for (index, icon) in icons.prefix(count).enumerated() {
            let x = bounds.width >= 48 ? 8 + CGFloat(index) * 18 : (bounds.width - 16) / 2
            let image: NSImage
            if icon.isTemplate {
                image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
                    icon.draw(in: rect)
                    NSColor.labelColor.setFill()
                    rect.fill(using: .sourceIn)
                    return true
                }
            } else { image = icon }
            image.draw(in: CGRect(x: x, y: 9, width: 16, height: 16), from: .zero, operation: .sourceOver,
                      fraction: 1, respectFlipped: true, hints: nil)
        }
        if model.pinned != nil, let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned") {
            let badge = NSImage(size: CGSize(width: 11, height: 11), flipped: false) { rect in
                pin.draw(in: rect)
                NSColor.controlAccentColor.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            badge.draw(in: CGRect(x: bounds.width - 16, y: 5, width: 11, height: 11), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        if bounds.width >= 48 {
            drawMinimapText(model.title, in: CGRect(x: 8, y: 34, width: bounds.width - 16, height: 16),
                            font: .systemFont(ofSize: 10, weight: focused ? .medium : .regular), color: .labelColor)
        }
        if model.count > 1, bounds.width >= 65 {
            let glyph = CGRect(x: bounds.width - 29, y: 9, width: 20, height: 16)
            NSColor.secondaryLabelColor.setStroke()
            // A stack: a tile divided top and bottom.
            do {
                NSBezierPath(roundedRect: glyph.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).stroke()
                let split = NSBezierPath()
                split.move(to: CGPoint(x: glyph.minX + 1, y: glyph.midY))
                split.line(to: CGPoint(x: glyph.maxX - 1, y: glyph.midY))
                split.stroke()
            }
        }
    }
}

@MainActor
private final class ScrollingMinimapViewport: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        outline.fill()
        NSColor.labelColor.withAlphaComponent(0.42).setStroke()
        outline.lineWidth = 1.5
        outline.setLineDash([3, 3], count: 2, phase: 0)
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
