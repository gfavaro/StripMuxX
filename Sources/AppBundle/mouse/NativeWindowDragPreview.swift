import AppKit
import Common

/// Observational drag hint. Does not move managed windows or interfere with the
/// native mouse stream; actual swaps are still decided by adoptNativeMouseRelease.
@MainActor
final class NativeWindowDragPreview {
    private weak var dragged: Window?
    private weak var workspace: Workspace?
    private var originalPoint: CGPoint = .zero
    private var sessionEpoch: UInt64 = 0
    private var homePanel: NSPanel?
    private var destinationPanel: NSPanel?
    private var dragEventMonitor: Any?
    private var expiry: Task<Void, Never>?

    func begin(at point: CGPoint) {
        hide()
        guard let window = focus.windowOrNil, let space = window.nodeWorkspace,
              space.isVisible, !window.isFullscreen,
              window.nativeLayoutEligible, window.parent is TilingContainer,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.pid,
              let rect = window.lastAppliedLayoutPhysicalRect,
              rect.contains(point), point.y - rect.minY <= 40, point.y >= rect.minY else { return }
        dragged = window
        workspace = space
        originalPoint = point
        sessionEpoch = space.scrollingSessionEpoch
        // Observe only a qualified drag, not every left-drag event systemwide.
        dragEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.moved(to: mouseLocation)
            }
        }
        armExpiry()
    }

    func moved(to point: CGPoint) {
        guard let dragged, let workspace,
              workspace.isVisible, workspace.scrollingSessionEpoch == sessionEpoch,
              dragged.nodeWorkspace === workspace, dragged.nativeLayoutEligible,
              dragged.parent is TilingContainer else { hide(); return }
        armExpiry()
        guard hypot(point.x - originalPoint.x, point.y - originalPoint.y) > 12 else { return }
        if let rect = dragged.lastAppliedLayoutPhysicalRect {
            if homePanel == nil { homePanel = Self.makePanel(color: .secondaryLabelColor, alpha: 0.45) }
            if let homePanel { show(homePanel, rect: rect, under: dragged.windowId) }
        }
        guard let target = nativeMouseSwapTarget(for: dragged, at: point),
              let rect = target.lastAppliedLayoutPhysicalRect else {
            destinationPanel?.orderOut(nil)
            return
        }
        if destinationPanel == nil { destinationPanel = Self.makePanel(color: .controlAccentColor, alpha: 0.85) }
        if let destinationPanel { show(destinationPanel, rect: rect, under: dragged.windowId) }
    }

    /// A missing mouse-up cannot leak a systemwide event observer or overlay.
    private func armExpiry() {
        expiry?.cancel()
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        expiry?.cancel()
        expiry = nil
        if let dragEventMonitor { NSEvent.removeMonitor(dragEventMonitor) }
        dragEventMonitor = nil
        dragged = nil
        workspace = nil
        homePanel?.orderOut(nil)
        destinationPanel?.orderOut(nil)
    }

    private func show(_ panel: NSPanel, rect: Rect, under _: UInt32) {
        // Layout uses top-left global coordinates; AppKit windows use bottom-left.
        // CGWindow/AX coordinates are top-left-relative to the primary
        // display. AppKit global coordinates are bottom-left-relative to
        // that same display. Use maxY, not height, for offset displays.
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ??
                NSScreen.main else { return }
        let frame = nativeDragOverlayFrame(for: rect, primaryScreenTop: primary.frame.maxY)
        guard frame.width > 0, frame.height > 0 else { return }
        if !panel.isVisible || panel.frame != frame { panel.setFrame(frame, display: true) }
        // NSWindow.order(relativeTo:) expects an NSWindow number, not a
        // CGWindowID from another application. A nonactivating floating
        // overlay with ignored mouse input is both visible and safe.
        panel.orderFrontRegardless()
    }

    private static func makePanel(color: NSColor, alpha: CGFloat) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        // Never join all Spaces: the overlay belongs to the desktop on
        // which the drag began, not to the next desktop after switching.
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.level = .floating
        panel.contentView = NativeWindowDragOutline(color: color, opacity: alpha)
        return panel
    }
}

private final class NativeWindowDragOutline: NSView {
    let color: NSColor
    let opacity: CGFloat

    init(color: NSColor, opacity: CGFloat) {
        self.color = color
        self.opacity = opacity
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        color.withAlphaComponent(opacity * 0.12).setFill()
        path.fill()
        color.withAlphaComponent(opacity).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}

/// Convert an already-observed physical AX frame to AppKit global coordinates.
/// Pure function to cover displays with negative X origins and vertical offsets.
func nativeDragOverlayFrame(for rect: Rect, primaryScreenTop: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
}
