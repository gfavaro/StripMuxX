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
    private var documentWindowCache: [UInt32: Bool] = [:]
    private var lastDragLocation: CGPoint?
    /// Owns the display-link subscription that follows a moving strip.
    private final class MotionOwner {}
    private let motionOwner = MotionOwner()
    private var motionDeadline: CFTimeInterval = 0

    /// Why borders disappeared since launch, for doctor.
    private(set) var hideCounts: [String: Int] = [:]
    private func count(_ reason: String) { hideCounts[reason, default: 0] += 1 }

    var backendDiagnosticSummary: String {
        let native = borders.values.filter(\.usesNativeBackend).count
        let hidden = hideCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        return "native=\(native) AppKitFallback=\(borders.count - native) activeBorders=\(borders.count); hidden: \(hidden.isEmpty ? "never" : hidden)"
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
    func hide(_ reason: String = "space change") {
        count("all, " + reason)
        isSuspended = true
        for border in borders.values { border.hide() }
        for border in spareBorders { border.hide() }
        DisplayRefreshDriver.shared.remove(owner: self)
        DisplayRefreshDriver.shared.remove(owner: motionOwner)
        motionDeadline = 0
    }

    func refresh() {
        guard !isUnitTest else { return }
        let settings = config.windowBorders
        guard TrayMenuModel.shared.isEnabled, settings.enabled, settings.width > 0,
              !serverArgs.isReadOnly else { clear(); return }
        guard !isSuspended else { return }
        // Mid-reconciliation, eligibility and membership are being rebuilt; removing a
        // border then only to restore it on accept makes it blink. accept() resumes.
        guard runtime.native.tiling.ready else { return }
        let activeDesktops = runtime.native.layouts.currentBySpaceID.values.filter { $0.isVisible }
        guard !activeDesktops.isEmpty else { clear(); return }

        // A transparent border (the default for unfocused windows) draws nothing, yet positioning
        // and redrawing it cost main-thread time on every display frame of a scroll, delaying the
        // scroll events that share that thread. Windows without a visible border are skipped.
        let activeShown = !windowBorderIsInvisible(settings.activeColor)
        let inactiveShown = !windowBorderIsInvisible(settings.inactiveColor)
        var visible = Set<UInt32>()
        for workspace in activeDesktops {
            guard nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else { continue }
            for window in workspace.allLeafWindowsRecursive {
                guard window.nativeLayoutEligible, window.participatesInWorkspaceFocus,
                      !window.isFullscreen, window.lastKnownNativeFullscreen != true,
                      window.lastKnownNativeMinimized != true, !window.isConcealedByScrolling else { continue }
                if let bundle = window.app.rawAppBundleId, settings.excludeApps.contains(bundle) { continue }
                guard focus.windowOrNil === window ? activeShown : inactiveShown else { continue }
                // Same SkyLight top-level document filter as WinMuxX. Unsupported
                // systems report -1 and retain the documented AX fallback.
                let eligible = documentWindowCache[window.windowId] ?? {
                    let result = winmux_window_document_kind(window.windowId)
                    return result != 0
                }()
                documentWindowCache[window.windowId] = eligible
                guard eligible else { continue }

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
            documentWindowCache[id] = nil
            guard let old = borders.removeValue(forKey: id) else { continue }
            count(id == focus.windowOrNil?.windowId ? "focused window left the visible set" : "window left the visible set")
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
        lastDragLocation = mouseLocation
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            guard let self else { return }
            guard NSEvent.pressedMouseButtons & 1 != 0 else {
                self.endDragging()
                return
            }
            let location = mouseLocation
            guard self.lastDragLocation != location else { return }
            self.lastDragLocation = location
            self.refresh()
        }
    }

    /// A strip that is panning or settling moves its windows through asynchronous AX
    /// writes, so a refresh when the layout returns reads where the windows were. Follow
    /// the WindowServer frames every display frame instead, until the strip has been still
    /// for `settle` seconds.
    func followStripMotion() {
        guard !isUnitTest, !isSuspended, config.windowBorders.enabled else { return }
        let alreadyFollowing = motionDeadline > CACurrentMediaTime()
        motionDeadline = CACurrentMediaTime() + 0.35
        guard !alreadyFollowing else { return }
        DisplayRefreshDriver.shared.add(owner: motionOwner) { [weak self] _ in
            guard let self else { return }
            let settled = CACurrentMediaTime() >= self.motionDeadline || self.isSuspended
            self.refresh()
            if settled { DisplayRefreshDriver.shared.remove(owner: self.motionOwner) }
        }
    }

    func endDragging() {
        lastDragLocation = nil
        DisplayRefreshDriver.shared.remove(owner: self)
        refresh()
    }

    func clear() {
        if !borders.isEmpty { count("all, cleared") }
        lastDragLocation = nil
        documentWindowCache.removeAll()
        DisplayRefreshDriver.shared.remove(owner: self)
        DisplayRefreshDriver.shared.remove(owner: motionOwner)
        motionDeadline = 0
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
