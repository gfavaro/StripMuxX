import AppKit
import Common

/// Pans the strip with Option + two-finger horizontal trackpad scroll, because
/// macOS keeps three- and four-finger swipes for switching Spaces.
/// Scroll events, including macOS's own momentum after lifting, move the viewport
/// directly and are consumed; when they stop, the column nearest the middle is
/// revealed and focused.
@MainActor
final class NativeScrollingPan {
    static let shared = NativeScrollingPan()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var workspace: Workspace?
    /// The topology/Space identity under which a gesture began.
    private var gestureEpoch: UInt64?
    private var gestureMonitor: String?
    var isPanning: Bool { workspace != nil }
    private var lastDirection: CGFloat = 0
    private var idleTask: Task<Void, Never>?
    /// Why the last Option scroll did or did not pan, for doctor.
    private(set) var lastDecision = "none"

    struct Scroll {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let isContinuous: Bool
        let optionOnly: Bool
        let phase: Int64
        let momentumPhase: Int64
        let point: CGPoint
    }

    func start() {
        guard tap == nil, !isUnitTest else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { NativeScrollingPan.shared.reenable() }
                    return Unmanaged.passUnretained(event)
                }
                let flags = event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
                let scroll = Scroll(
                    deltaX: CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)),
                    deltaY: CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)),
                    isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                    optionOnly: flags == .maskAlternate,
                    phase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
                    momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
                    point: event.location)
                let consumed = MainActor.assumeIsolated {
                    PublicGestureProbe.shared.observeCGScroll(scroll)
                    return nativePanTiming.measure("scroll event") { NativeScrollingPan.shared.handle(scroll) }
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: nil) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// Returns whether the event belongs to a pan and must not reach the app.
    func handle(_ scroll: Scroll) -> Bool {
        if let workspace {
            // A stale Space, display or session cannot own any further scroll events.
            // Do not focus another column while cancelling a superseded interaction.
            guard workspace.isVisible, workspace.scrollingSessionEpoch == gestureEpoch,
                  workspace.workspaceMonitor.displayUUID == gestureMonitor,
                  config.scrolling.gestureEnabled, TrayMenuModel.shared.isEnabled,
                  nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else {
                cancel()
                lastDecision = "gesture cancelled: desktop or session changed"
                return false
            }
            // A new non-Option gesture belongs to the foreground app. Never snap
            // focus to another window as a side effect of that unrelated gesture.
            if scroll.momentumPhase == 0, scroll.phase == 1, !scroll.optionOnly {
                cancel()
                return false
            }
            pan(workspace, by: scroll.deltaX)
            if scroll.momentumPhase == 3 { settle() } else { settleWhenIdle() }
            return true
        }
        guard scroll.optionOnly, scroll.isContinuous, scroll.momentumPhase == 0 else { return false }
        guard config.scrolling.gestureEnabled, TrayMenuModel.shared.isEnabled else {
            lastDecision = "scrolling gestures or StripMuxX are off"; return false
        }
        guard abs(scroll.deltaX) > abs(scroll.deltaY) else { lastDecision = "vertical: left to the app"; return false }
        guard let monitor = sortedMonitors.first(where: { $0.rect.contains(scroll.point) }),
              let target = nativeActiveDesktop(on: monitor), target.isVisible else {
            lastDecision = "no desktop under the pointer"; return false
        }
        workspace = target
        gestureEpoch = target.scrollingSessionEpoch
        gestureMonitor = target.workspaceMonitor.displayUUID
        lastDirection = 0
        lastDecision = "panning"
        target.scrollingGestureMotionActive = true
        // A session streams window moves without per-step readback.
        target.scrollingGestureSessionID = UUID()
        pan(target, by: scroll.deltaX)
        settleWhenIdle()
        return true
    }

    private func pan(_ workspace: Workspace, by deltaX: CGFloat) {
        let metrics = workspace.scrollingMetrics
        let current = metrics.clampedOffset(workspace.scrollingOffset)
        // Content follows the fingers: moving them left reveals columns to the right.
        let next = metrics.clampedOffset(current - deltaX * CGFloat(config.scrolling.gestureSensitivity))
        if next != current { lastDirection = next > current ? 1 : -1 }
        workspace.scrollingOffset = next
        nativePanTiming.measure("minimap show") { _ = WorkspaceScrollingMinimap.shared.show(workspace, duringGesture: true) }
        nativePanTiming.measure("relayout request") { runtime.native.tiling.relayoutVisibleScrolling() }
    }

    /// Devices without scroll phases end a pan after a pause.
    private func settleWhenIdle() {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }

    /// Abandon a gesture when another desktop or user interaction takes ownership.
    /// No focus transfer, no snap: the user explicitly changed the interaction.
    func cancel() {
        finishGesture(focusNearest: false)
    }

    func settle() {
        finishGesture(focusNearest: true)
    }

    private func finishGesture(focusNearest: Bool) {
        idleTask?.cancel()
        idleTask = nil
        guard let workspace else { return }
        self.workspace = nil
        gestureEpoch = nil
        gestureMonitor = nil
        workspace.scrollingGestureMotionActive = false
        workspace.scrollingGestureSessionID = nil
        WorkspaceScrollingMinimap.shared.endGesture()
        // One fresh native read after the gesture is complete. Never retain
        // stale write authority from a previous Space while finishing.
        defer { runtime.native.observation?.requestRead(event: "nativeScrollingSettled") }
        guard focusNearest, workspace.isVisible,
              nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else {
            return
        }
        let metrics = workspace.scrollingMetrics
        guard let column = nearestScrollingColumn(in: metrics, offset: workspace.scrollingOffset, direction: lastDirection) else {
            return runtime.native.tiling.relayoutVisibleScrolling()
        }
        workspace.scrollingOffset = metrics.focusedOffset(for: column, current: workspace.scrollingOffset)
        if let window = column.node.mostRecentWindowRecursive, window.focusWindow() {
            workspace.lastScrollingFocusWindowId = window.windowId
            window.nativeFocus()
        }
        runtime.native.tiling.relayoutVisibleScrolling()
        _ = WorkspaceScrollingMinimap.shared.show(workspace)
    }
}

/// Geometry notifications a pan's own window moves produce.
/// Geometry and focus notifications a pan's own moves and raises produce; none of them
/// changes which windows belong to the desktop.
func nativePanIgnoresNotification(_ notif: String) -> Bool {
    notif == kAXMovedNotification as String || notif == kAXResizedNotification as String ||
        notif == kAXWindowMovedNotification as String || notif == kAXWindowResizedNotification as String ||
        notif == kAXFocusedWindowChangedNotification as String
}

/// The column whose centre is nearest the viewport's centre; ties follow the last
/// movement direction.
func nearestScrollingColumn(in metrics: ScrollingWorkspaceMetrics, offset: CGFloat, direction: CGFloat) -> ScrollingColumnMetric? {
    let center = offset + metrics.areaWidth / 2
    return metrics.columns.min { lhs, rhs in
        let a = abs(lhs.start + lhs.width / 2 - center)
        let b = abs(rhs.start + rhs.width / 2 - center)
        if abs(a - b) < 0.5, direction != 0 { return direction > 0 ? lhs.start > rhs.start : lhs.start < rhs.start }
        return a < b
    }
}
