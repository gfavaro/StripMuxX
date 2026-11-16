import AppKit
import Common
import PrivateApi
import QuartzCore

// WinMuxX native eight-piece border renderer and exact click-through AppKit fallback.
// Kept verbatim aside from the separation from WinMuxX workspace lifecycle.

@MainActor
final class WindowBorder {
    private(set) var target: UInt32
    /// The window the native pieces were last ordered against.
    private var placedTarget: UInt32?
    private var nativeID: OpaquePointer?
    private var frame: CGRect?
    private var geometry: WindowBorderGeometry?
    private var corners: WindowBorderCornerRadii?
    private var appearance: Appearance?
    private var scale: CGFloat = 0
    private var fallbackPanels: [WindowBorderFallbackPanel] = []
    private let createNativeBorder: (Float, inout OpaquePointer?) -> Bool
    private let updateNativeBorder: (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool, CGPath?) -> Bool
    private let destroyNativeBorder: (OpaquePointer?) -> Void

    var windowIds: [UInt32] {
        if let nativeID { return (0..<Int(WINMUX_BORDER_PIECES)).map { winmux_border_window_id(nativeID, Int32($0)) }.filter { $0 != 0 } }
        return fallbackPanels.map { UInt32(max($0.windowNumber, 0)) }.filter { $0 != 0 }
    }

    var windowId: UInt32 { windowIds.first ?? 0 }

    func retarget(_ target: UInt32) -> WindowBorder {
        self.target = target
        return self
    }
    var usesNativeBackend: Bool { nativeID != nil }

    init(
        target: UInt32,
        createNativeBorder: @escaping (Float, inout OpaquePointer?) -> Bool = { scale, id in winmux_border_create(scale, &id) },
        updateNativeBorder: @escaping (OpaquePointer?, UInt32, CGRect, Float, UInt32, Float, Bool, CGPath?) -> Bool = winmux_border_update,
        destroyNativeBorder: @escaping (OpaquePointer?) -> Void = winmux_border_destroy
    ) {
        self.target = target
        self.createNativeBorder = createNativeBorder
        self.updateNativeBorder = updateNativeBorder
        self.destroyNativeBorder = destroyNativeBorder
    }

    isolated deinit {
        if let nativeID { destroyNativeBorder(nativeID) }
        fallbackPanels.forEach { $0.close() }
    }

    func update(frame: CGRect, active: Bool, settings: WindowBordersConfig, corners: WindowBorderCornerRadii? = nil) {
        let display = monitors.first { $0.rect.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            .map { CGRect(x: $0.rect.minX, y: $0.rect.minY, width: $0.rect.width, height: $0.rect.height) }
        let onDisplay = windowBorderFrame(frame, width: CGFloat(settings.width), within: display)
        let nextCorners = corners ?? .init(top: systemWindowCornerRadius(), bottom: systemWindowCornerRadius())
        var cocoaFrame = CGRect(x: onDisplay.minX, y: mainMonitor.height - onDisplay.maxY,
                                width: onDisplay.width, height: onDisplay.height)
        let center = CGPoint(x: cocoaFrame.midX, y: cocoaFrame.midY)
        let nextScale = NSScreen.screens.first(where: { $0.frame.contains(center) })?.backingScaleFactor ?? 2
        let frame = pixelAlignedWindowBorderFrame(onDisplay, width: CGFloat(settings.width), scale: nextScale)
        cocoaFrame = CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY,
            width: frame.width, height: frame.height)
        if !fallbackPanels.isEmpty {
            updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
            return
        }
        if nativeID == nil || scale != nextScale {
            if let nativeID { destroyNativeBorder(nativeID) }
            nativeID = nil
            guard createNativeBorder(Float(nextScale), &nativeID) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
            scale = nextScale
            self.frame = nil
            appearance = nil
        }
        let nextAppearance = Appearance(settings: settings, active: active)
        if appearance == nextAppearance, self.frame == frame, self.corners == nextCorners, placedTarget == target { return }
        if appearance != nextAppearance || self.frame?.size != frame.size || self.corners != nextCorners {
            let radius = nextCorners.maximum
            let outerSize = frame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width)).size
            let path = borderGeometry(size: outerSize, corners: nextCorners, width: CGFloat(settings.width), scale: nextScale).path
            guard updateNativeBorder(nativeID, target, frame, Float(radius),
                                       nextAppearance.rgba, Float(settings.width), settings.order == .above, path) else {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
            appearance = nextAppearance
        } else {
            if !winmux_border_move(nativeID, target, frame, Float(settings.width), settings.order == .above) {
                if let nativeID { destroyNativeBorder(nativeID) }
                nativeID = nil
                updateFallback(frame: cocoaFrame, active: active, settings: settings, scale: nextScale, corners: nextCorners)
                return
            }
        }
        self.frame = frame
        self.corners = nextCorners
        placedTarget = target
    }

    private func borderGeometry(size: CGSize, corners: WindowBorderCornerRadii, width: CGFloat, scale: CGFloat) -> WindowBorderGeometry {
        let bottomRadius = corners.bottom == corners.top ? nil : corners.bottom
        let key = WindowBorderGeometry.Key(size: size, radius: corners.top, width: width, scale: scale, bottomRadius: bottomRadius)
        if let geometry, geometry.key == key { return geometry }
        let updated = WindowBorderGeometry(size: size, radius: corners.top, width: width, scale: scale, bottomRadius: bottomRadius)
        geometry = updated
        return updated
    }

    private func updateFallback(frame: CGRect, active: Bool, settings: WindowBordersConfig, scale: CGFloat, corners: WindowBorderCornerRadii) {
        if fallbackPanels.isEmpty { fallbackPanels = (0..<Int(WINMUX_BORDER_PIECES)).map { _ in WindowBorderFallbackPanel() } }
        let alignedFrame = pixelAlignedWindowBorderFrame(frame, width: CGFloat(settings.width), scale: scale)
        let outer = alignedFrame.insetBy(dx: -CGFloat(settings.width), dy: -CGFloat(settings.width))
        let radius = corners.maximum
        let path = borderGeometry(size: outer.size, corners: corners, width: CGFloat(settings.width), scale: scale).path
        for (index, panel) in fallbackPanels.enumerated() {
            let piece = winmux_border_piece(outer.size, Float(radius), Float(settings.width), Float(scale), Int32(index))
            panel.update(outer: outer, piece: piece, radius: radius, path: path, windowId: target, active: active, settings: settings)
        }
    }

    /// Orders the border out but keeps its windows for the next target.
    func hide() {
        if let nativeID { winmux_border_hide(nativeID) }
        fallbackPanels.forEach { $0.orderOut(nil) }
        placedTarget = nil
    }

    func destroy() {
        if let nativeID {
            winmux_border_hide(nativeID)
            destroyNativeBorder(nativeID)
            self.nativeID = nil
        }
        fallbackPanels.forEach { $0.close() }
        fallbackPanels.removeAll()
    }
}

/// The resolved color is part of the value: an accent change redraws on the next refresh.
@MainActor
private struct Appearance: Equatable {
    let settings: WindowBordersConfig
    let rgba: UInt32
    init(settings: WindowBordersConfig, active: Bool) {
        self.settings = settings
        rgba = windowBorderRGBA(active ? settings.activeColor : settings.inactiveColor)
    }
}


// Public AppKit fallback when the private WindowServer renderer is unavailable.
@MainActor
private final class WindowBorderFallbackPanel: NSPanelHud {
    private let borderView = WindowBorderFallbackView()


    override init() {
        super.init()
        level = .normal
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        // Transient panels are hidden by Exposé/Mission Control. Stationary panels
        // deliberately remain visible there, even before our next refresh can detect it.
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = borderView
        borderView.autoresizingMask = [.width, .height]
    }

    // Edge panels must retain their exact coordinates across menu-bar boundaries.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(outer: CGRect, piece: CGRect, radius: CGFloat, path: CGPath, windowId: UInt32, active: Bool, settings: WindowBordersConfig) {
        guard !piece.isEmpty else { orderOut(nil); return }
        let frame = CGRect(x: outer.minX + piece.minX, y: outer.maxY - piece.maxY,
            width: piece.width, height: piece.height)
        if self.frame != frame { setFrame(frame, display: false) }
        // The path is rebuilt for every update: compared by identity it always differed, and
        // every piece redrew on each focus or geometry refresh even when nothing changed.
        let geometryChanged = borderView.outerSize != outer.size || borderView.piece != piece || borderView.radius != radius || borderView.path != path
        let rgba = windowBorderRGBA(active ? settings.activeColor : settings.inactiveColor)
        if geometryChanged || borderView.rgba != rgba {
            borderView.rgba = rgba
            borderView.outerSize = outer.size
            borderView.piece = piece
            borderView.radius = radius
            borderView.path = path
            borderView.needsDisplay = true
        }
        order(settings.order == .above ? .above : .below, relativeTo: Int(windowId))
    }
}

@MainActor
private final class WindowBorderFallbackView: NSView {
    override var isFlipped: Bool { true }
    var rgba: UInt32 = 0
    var outerSize = CGSize.zero
    var piece = CGRect.zero
    var radius: CGFloat = 0
    var path: CGPath?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let path { winmux_border_draw_path(context, piece, path, rgba) }
    }
}
