import AppKit
import Common

/// Lightweight AppKit port of WinMuxX's click-through focused-window border.
///
/// The original WinMuxX border renderer depends on private WindowServer
/// primitives and virtual workspace notifications. StripMuxX keeps only the
/// visual contract: a 4-point accent border, transparent inactive state, and
/// no interaction or native Space ownership changes.
@MainActor
final class NativeWindowBorder {
    static let shared = NativeWindowBorder()

    static let width: CGFloat = 4
    private var panel: NativeWindowBorderPanel?
    private var currentWindowID: UInt32?
    private var lastFrame: CGRect?

    /// Called by the native layout and focus paths. Never queries AX, creates
    /// Spaces, focuses an app, or changes a managed window's geometry.
    func refresh() {
        guard !isUnitTest else { return }
        guard TrayMenuModel.shared.isEnabled,
              let window = focus.windowOrNil,
              let workspace = window.nodeWorkspace, workspace.isVisible,
              window.nativeLayoutEligible, !window.isFullscreen,
              window.lastKnownNativeFullscreen != true,
              !window.isConcealedByScrolling,
              nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace,
              let rect = window.lastAppliedLayoutPhysicalRect ?? (window.isFloating ? window.lastKnownActualRect : nil),
              rect.width > 0, rect.height > 0 else {
            hide()
            return
        }

        let native = CGRect(origin: rect.topLeftCorner, size: rect.size)
        let frame = Self.panelFrame(for: native, mainDisplayHeight: mainMonitor.height)
        let panel = self.panel ?? NativeWindowBorderPanel()
        self.panel = panel
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if currentWindowID != window.windowId || lastFrame != frame || !panel.isVisible {
            panel.order(.above, relativeTo: Int(window.windowId))
            currentWindowID = window.windowId
            lastFrame = frame
        }
    }

    static func panelFrame(for native: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        let width = Self.width
        return CGRect(x: native.minX - width,
                      y: mainDisplayHeight - native.maxY - width,
                      width: native.width + width * 2,
                      height: native.height + width * 2)
    }

    func hide() {
        panel?.orderOut(nil)
        currentWindowID = nil
        lastFrame = nil
    }
}

@MainActor
private final class NativeWindowBorderPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hasShadow = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        isOpaque = false
        backgroundColor = .clear
        level = .normal
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = NativeWindowBorderView()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NativeWindowBorderView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let thickness = NativeWindowBorder.width
        let outline = bounds.insetBy(dx: thickness / 2, dy: thickness / 2)
        let path = NSBezierPath(roundedRect: outline, xRadius: 12, yRadius: 12)
        path.lineWidth = thickness
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
