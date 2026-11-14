import AppKit
import Common

/// Asks for the showing desktops to be laid out again. A change that only moves the strip
/// or edits its tree is laid out at once under the current write permits; anything else
/// asks for a fresh observation, which reconciles windows and then lays out.
@MainActor
func scheduleRefreshSession(_ event: RefreshSessionEvent) {
    if case .globalObserver(let name) = event, nativeScrollingRelayoutEvents.contains(name) {
        return runtime.native.tiling.relayoutVisibleScrolling()
    }
    runtime.native.observation?.requestRead(event: "refresh")
}

/// Events that change only the strip's offset or its in-memory tree, never which windows a
/// desktop owns. Listed explicitly, not by name prefix.
let nativeScrollingRelayoutEvents: Set<String> = [
    "scrollingCenter", "scrollingMinimapSelection", "scrollingMove", "scrollingPin", "scrollingWidth",
    "moveScrollingColumn", "moveWithinScrollingColumn", "resizeScrollingColumn", "joinScrolling",
]

/// Proof that StripMuxX is enabled, or that the caller may run while it is not.
struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

/// An AX notification from an app: its windows may have changed, so the desktops are read again.
func refreshObs(_: AXObserver, _ ax: AXUIElement, notif: CFString, _ context: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let isDestroyed = notif == kAXUIElementDestroyedNotification as String
    let emittingAppPid = axTaskLocalAppThreadToken?.pid
    Task { @MainActor in
        if isDestroyed { windowLifecycleChanges.notify() }
        // A sheet appearing or going away changes what the strip reveals.
        if let emittingAppPid,
           notif == kAXSheetCreatedNotification as String || notif == kAXFocusedWindowChangedNotification as String ||
            notif == kAXWindowCreatedNotification as String || isDestroyed {
            for window in MacWindow.allWindows where window.macApp.pid == emittingAppPid {
                window.invalidateScrollingSheetCache()
            }
        }
        // A pan's own window moves must not revoke the permits it is streaming
        // with; the pan reads once when it settles.
        if NativeScrollingPan.shared.isPanning, nativePanIgnoresNotification(notif) { return }
        runtime.native.writeAuthority.invalidate()
        runtime.native.observation?.requestRead(event: "axWindowChange")
    }
}

/// A window moved or resized: one its app moved by itself is put back on its tile.
func geometryObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    Task { @MainActor in runtime.native.windowGeometryChanged(windowId) }
}
