import AppKit
import Common
import PrivateApi

/// WinMuxX's per-window border engine bound to StripMuxX's native Spaces.
/// Only the lifecycle glue differs: the renderer itself is the original
/// eight-piece WindowServer implementation, with its exact AppKit fallback.
@MainActor
final class NativeWindowBorder {
    static let shared = NativeWindowBorder()

    private var borders: [UInt32: WindowBorder] = [:]
    private var spareBorders: [WindowBorder] = []
    private let spareBorderLimit = 4
    private var nativeBordersUnavailable = false
    private var colorObservers: [Any] = []
    private var isSuspended = false

    var backendDiagnosticSummary: String {
        let native = borders.values.filter(\.usesNativeBackend).count
        return "native=\(native) AppKitFallback=\(borders.count - native) activeBorders=\(borders.count)"
    }

    func startColorMonitoring() {
        guard !isUnitTest, colorObservers.isEmpty else { return }
        colorObservers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { NativeWindowBorder.shared.refresh() }
            })
        if let app = NSApp {
            colorObservers.append(app.observe(\.effectiveAppearance) { _, _ in
                Task { @MainActor in NativeWindowBorder.shared.refresh() }
            })
        }
    }

    /// A native Space / Mission Control transition invalidates the display
    /// inventory. Hide rather than moving borders to a different desktop.
    func hide() {
        isSuspended = true
        for border in borders.values { border.hide() }
        for border in spareBorders { border.hide() }
        DisplayRefreshDriver.shared.remove(owner: self)
    }

    func refresh() {
        guard !isUnitTest else { return }
        let settings = config.windowBorders
        guard TrayMenuModel.shared.isEnabled, settings.enabled, settings.width > 0,
              !serverArgs.isReadOnly else { clear(); return }
        guard !isSuspended else { return }
        let activeDesktops = runtime.native.layouts.currentBySpaceID.values.filter { $0.isVisible }
        guard !activeDesktops.isEmpty else { clear(); return }

        var visible = Set<UInt32>()
        for workspace in activeDesktops {
            guard nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else { continue }
            for window in workspace.allLeafWindowsRecursive {
                guard window.nativeLayoutEligible, window.participatesInWorkspaceFocus,
                      !window.isFullscreen, window.lastKnownNativeFullscreen != true,
                      window.lastKnownNativeMinimized != true, !window.isConcealedByScrolling else { continue }
                if let bundle = window.app.rawAppBundleId, settings.excludeApps.contains(bundle) { continue }

                // Prefer the WindowServer frame, as WinMuxX does. AX writes on a
                // moving strip can still be pending when the layout completes.
                var native = CGRect.zero
                let frame: CGRect
                if winmux_window_frame(window.windowId, &native), native.width > 0, native.height > 0 {
                    frame = native
                } else if let target = window.lastAppliedLayoutPhysicalRect ??
                    (window.isFloating ? window.lastKnownActualRect : nil) {
                    frame = CGRect(origin: target.topLeftCorner, size: target.size)
                } else { continue }

                guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite,
                      frame.minY.isFinite, frame.width > 0, frame.height > 0 else { continue }
                visible.insert(window.windowId)
                let border: WindowBorder
                if let existing = borders[window.windowId] {
                    border = existing
                } else if let spare = spareBorders.popLast() {
                    border = spare.retarget(window.windowId)
                    borders[window.windowId] = border
                } else {
                    border = nativeBordersUnavailable
                        ? WindowBorder(target: window.windowId, createNativeBorder: { _, _ in false })
                        : WindowBorder(target: window.windowId)
                    borders[window.windowId] = border
                }
                let radius = systemWindowCornerRadius()
                border.update(frame: frame, active: focus.windowOrNil === window, settings: settings,
                              corners: .init(top: radius, bottom: radius))
                if !border.usesNativeBackend { nativeBordersUnavailable = true }
            }
        }

        // Never leave an overlay on a closed, parked, excluded or removed window.
        for id in Array(borders.keys) where !visible.contains(id) {
            guard let old = borders.removeValue(forKey: id) else { continue }
            old.hide()
            if spareBorders.count < spareBorderLimit { spareBorders.append(old) }
            else { old.destroy() }
        }
    }

    /// Called only when the native observation has accepted a desktop again.
    func resume() {
        isSuspended = false
        startColorMonitoring()
        refresh()
    }

    /// A user drag leaves the regular layout loop paused. Follow the frontmost
    /// window with the same WindowServer geometry and renderer used by WinMuxX.
    func beginDragging() {
        guard !isUnitTest, !isSuspended, config.windowBorders.enabled else { return }
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            guard let self else { return }
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                self.endDragging()
                return
            }
            self.refresh()
        }
    }

    func endDragging() {
        DisplayRefreshDriver.shared.remove(owner: self)
        refresh()
    }

    func clear() {
        DisplayRefreshDriver.shared.remove(owner: self)
        for border in borders.values { border.destroy() }
        for border in spareBorders { border.destroy() }
        borders.removeAll()
        spareBorders.removeAll()
    }
}

/// The ordinary macOS window radius used by WinMuxX's regular-window target.
/// The strip has no WinMuxX tab-bar chrome, so its corners are symmetrical.
struct WindowBorderCornerRadii: Equatable {
    let top: CGFloat
    let bottom: CGFloat
    var maximum: CGFloat { max(top, bottom) }
}

func systemWindowCornerRadius() -> CGFloat { 12 }
