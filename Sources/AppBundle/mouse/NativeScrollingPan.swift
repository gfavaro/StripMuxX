import AppKit
import Common

/// Pans the strip with Option + two-finger horizontal trackpad scroll, because
/// macOS keeps three- and four-finger swipes for switching Spaces.
/// Scroll events, including macOS's own momentum after lifting, move the viewport
/// directly and are consumed; on release focus follows the nearest column
/// without shifting the camera again. Two-finger panning never changes focus.
@MainActor
final class NativeScrollingPan {
    static let shared = NativeScrollingPan()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private weak var workspace: Workspace?
    /// The topology/Space identity under which a gesture began.
    private var gestureEpoch: UInt64?
    private var gestureMonitor: String?
    private var dockSwipeProgress: Double = 0
    private var dockSwipeSign: Double = 1
    /// Purely observational: understand reports of wide columns being hard to exit.
    private var dockSwipeStartingColumn: ObjectIdentifier?
    private var dockSwipeStartingWidth: CGFloat = 0
    private var dockSwipeMaximumProgress: Double = 0
    private var dockSwipeCommitted = false
    private(set) var lastDockSwipeReport = "none"
    private(set) var isDockSwipeActive = false
    var isPanning: Bool { workspace != nil }
    private var lastDirection: CGFloat = 0
    private var resizingColumn = false
    /// After a resize ends with the fingers, macOS still streams that gesture's momentum.
    /// It belongs to the resize: swallow it, changing nothing, until it ends.
    private var absorbingResizeMomentum = false
    private weak var resizeWindow: Window?
    private var idleTask: Task<Void, Never>?
    /// Why the last Option scroll did or did not pan, for doctor.
    private(set) var lastDecision = "none"

    struct Scroll {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let isContinuous: Bool
        let optionOnly: Bool
        var resizeOnly: Bool = false
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
                    resizeOnly: flags == [.maskAlternate, .maskShift],
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
        if absorbingResizeMomentum {
            if scroll.momentumPhase != 0 {
                if scroll.momentumPhase == 3 { absorbingResizeMomentum = false }
                return true
            }
            absorbingResizeMomentum = false
        }
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
            if resizingColumn {
                // Direct resize ends with the fingers, not with kinetic momentum:
                // coasting should never continue to alter a window's size.
                if scroll.phase == 4 || scroll.momentumPhase != 0 {
                    settle()
                    absorbingResizeMomentum = scroll.momentumPhase != 3
                    return true
                }
                if scroll.phase == 1 && !scroll.resizeOnly {
                    cancel()
                    return false
                }
                guard scroll.resizeOnly, let window = resizeWindow,
                      window.nodeWorkspace === workspace, window.parent is TilingContainer else {
                    cancel()
                    return false
                }
                resizeFocusedColumn(window, in: workspace, by: scroll.deltaX)
                settleWhenIdle()
                return true
            }
            // A new non-Option gesture belongs to the foreground app. Never snap
            // focus to another window as a side effect of that unrelated gesture.
            if scroll.momentumPhase == 0, scroll.phase == 1, !scroll.optionOnly {
                cancel()
                return false
            }
            // Finger lift may precede macOS momentum by a few frames.
            // Don't settle the camera or focus while waiting for that handoff.
            if scroll.momentumPhase == 3 {
                settle()
            } else {
                pan(workspace, by: scroll.deltaX)
                settleWhenIdle(awaitingMomentum: scroll.phase == 4)
            }
            return true
        }
        guard (scroll.optionOnly || scroll.resizeOnly), scroll.isContinuous,
              scroll.momentumPhase == 0 else { return false }
        guard config.scrolling.gestureEnabled, TrayMenuModel.shared.isEnabled else {
            lastDecision = "scrolling gestures or StripMuxX are off"; return false
        }
        guard abs(scroll.deltaX) > abs(scroll.deltaY) else { lastDecision = "vertical: left to the app"; return false }
        guard let monitor = sortedMonitors.first(where: { $0.rect.contains(scroll.point) }),
              let target = nativeActiveDesktop(on: monitor), target.isVisible else {
            lastDecision = "no desktop under the pointer"; return false
        }
        let resizing = scroll.resizeOnly
        let resizingWindow = focus.windowOrNil
        if resizing {
            guard let resizingWindow, resizingWindow.nodeWorkspace === target,
                  resizingWindow.parent is TilingContainer, !resizingWindow.isFullscreen,
                  resizingWindow.nativeLayoutEligible else {
                lastDecision = "resize needs a focused tiled window on this desktop"
                return false
            }
        }
        workspace = target
        resizingColumn = resizing
        resizeWindow = resizing ? resizingWindow : nil
        gestureEpoch = target.scrollingSessionEpoch
        gestureMonitor = target.workspaceMonitor.displayUUID
        lastDirection = 0
        lastDecision = resizing ? "resizing column" : "panning"
        target.scrollingGestureMotionActive = true
        // A session streams window moves without per-step readback.
        target.scrollingGestureSessionID = UUID()
        if resizing, let resizingWindow {
            resizeFocusedColumn(resizingWindow, in: target, by: scroll.deltaX)
        } else {
            pan(target, by: scroll.deltaX)
        }
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
        nativePanTiming.measure("relayout request") { runtime.native.tiling.relayoutVisibleScrolling(target: workspace) }
    }

    /// An explicit Option+Shift two-finger scroll resizes the focused column
    /// without claiming ordinary app scrolling or the Option-only pan gesture.
    private func resizeFocusedColumn(_ window: Window, in workspace: Workspace, by deltaX: CGFloat) {
        guard deltaX.isFinite, abs(deltaX) > 0.01,
              let column = workspace.scrollingMetrics.columns.first(where: {
                  $0.node === window.topLevelWorkspaceGroup
              }) else { return }
        let requested = max(minimumTiledResizeWeight,
                            column.width + deltaX * CGFloat(config.scrolling.gestureSensitivity))
        guard abs(requested - column.width) >= 0.5 else { return }
        let applied: CGFloat?
        if singleWindowWidthTarget(in: workspace) === window {
            applied = applySingleWindowManualResize(window, width: requested) ? requested : nil
        } else {
            applied = resizeColumn(of: window, toWidth: requested, in: workspace)
        }
        guard applied != nil else { return }
        _ = WorkspaceScrollingMinimap.shared.show(workspace, duringGesture: true)
        runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
    }

    /// A macOS-recognized three-finger Dock swipe drives the same viewport and
    /// layout engine as Option-scroll. The source owns event arbitration.
    func beginDockSwipe(positive: Bool, progress: Double) -> Bool {
        guard !isPanning, config.scrolling.gestureEnabled, config.scrolling.threeFingerSwipe,
              TrayMenuModel.shared.isEnabled,
              let monitor = sortedMonitors.first(where: { $0.rect.contains(mouseLocation) }),
              let target = nativeActiveDesktop(on: monitor), target.isVisible else { return false }
        workspace = target
        gestureEpoch = target.scrollingSessionEpoch
        gestureMonitor = target.workspaceMonitor.displayUUID
        isDockSwipeActive = true
        dockSwipeSign = positive ? 1 : -1
        dockSwipeProgress = 0
        dockSwipeMaximumProgress = 0
        let metrics = target.scrollingMetrics
        let startingColumn = nearestScrollingColumn(in: metrics, offset: target.scrollingOffset, direction: 0)
        dockSwipeStartingColumn = startingColumn.map { ObjectIdentifier($0.node) }
        dockSwipeStartingWidth = startingColumn?.width ?? 0
        lastDirection = 0
        target.scrollingGestureMotionActive = true
        target.scrollingGestureSessionID = UUID()
        updateDockSwipe(progress)
        return true
    }

    func updateDockSwipe(_ progress: Double) {
        guard let workspace, workspace.isVisible, workspace.scrollingSessionEpoch == gestureEpoch,
              workspace.workspaceMonitor.displayUUID == gestureMonitor,
              nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else { cancel(); return }
        let next = max(0, min(1, progress))
        let delta = next - dockSwipeProgress
        dockSwipeProgress = next
        dockSwipeMaximumProgress = max(dockSwipeMaximumProgress, next)
        if abs(delta) > 0.00001 {
            // Positive Dock progress corresponds to fingers moving left.
            pan(workspace, by: -CGFloat(delta * dockSwipeSign) * workspace.scrollingMetrics.areaWidth)
        }
    }

    /// The Dock's release decision is independent of viewport movement.
    /// Committed swipes may advance one neighboring column if a wide tile
    /// otherwise absorbs the entire finger-following displacement.
    func endDockSwipe() {
        dockSwipeCommitted = true
        settle()
    }

    /// Backstop for phase-less devices and interrupted momentum streams.
    /// Allow longer for the touch-to-momentum handoff.
    private func settleWhenIdle(awaitingMomentum: Bool = false) {
        idleTask?.cancel()
        idleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(awaitingMomentum ? 420 : 250)) }
            catch { return }
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
        let wasResizing = resizingColumn
        resizingColumn = false
        resizeWindow = nil
        // Two-finger pan changes the camera only. Native focus may change solely
        // for an explicitly committed Dock column swipe, never for a pan lift.
        let shouldFocus = isDockSwipeActive && focusNearest && !wasResizing
        let committedDockSwipe = isDockSwipeActive && dockSwipeCommitted && shouldFocus
        let metricsAtRelease = workspace.scrollingMetrics
        let settleColumn = settledDockSwipeColumn(in: metricsAtRelease, offset: workspace.scrollingOffset,
            direction: lastDirection, startingColumnID: dockSwipeStartingColumn,
            advanceIfStuck: committedDockSwipe)
        if isDockSwipeActive {
            let nearest = nearestScrollingColumn(in: metricsAtRelease, offset: workspace.scrollingOffset, direction: lastDirection)
            let moved = nearest.map { ObjectIdentifier($0.node) != dockSwipeStartingColumn } ?? false
            let assisted = committedDockSwipe && !moved &&
                settleColumn.map { ObjectIdentifier($0.node) != dockSwipeStartingColumn } == true
            lastDockSwipeReport = String(format: "max progress %.2f, starting width %.2f viewports, nearest changed %@, advance assist %@, committed %@",
                dockSwipeMaximumProgress,
                Double(dockSwipeStartingWidth / max(metricsAtRelease.areaWidth, 1)),
                moved ? "yes" : "no", assisted ? "yes" : "no",
                committedDockSwipe ? "yes" : "no")
        }
        dockSwipeStartingColumn = nil
        dockSwipeStartingWidth = 0
        dockSwipeMaximumProgress = 0
        dockSwipeCommitted = false
        self.workspace = nil
        gestureEpoch = nil
        gestureMonitor = nil
        dockSwipeProgress = 0
        isDockSwipeActive = false
        workspace.scrollingGestureMotionActive = false
        workspace.scrollingGestureSessionID = nil
        WorkspaceScrollingMinimap.shared.endGesture()
        // One fresh native read after the gesture is complete. Never retain
        // stale write authority from a previous Space while finishing.
        defer { runtime.native.observation?.requestRead(event: "nativeScrollingSettled") }
        guard workspace.isVisible,
              nativeActiveDesktop(on: workspace.workspaceMonitor) === workspace else { return }
        guard shouldFocus else {
            // Flush the final camera position to the relayout/persistence pipeline
            // without activating any application or snapping the camera.
            runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
            return
        }
        let metrics = workspace.scrollingMetrics
        guard let column = settleColumn else {
            return runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
        }
        // A continuous two-finger pan is direct manipulation: the viewport must
        // remain exactly where the gesture and macOS momentum left it. Selecting
        // the nearest window should not introduce a second, command-like snap.
        // Keep the deliberate column advancement for a committed Dock swipe.
        workspace.scrollingOffset = scrollingPanReleaseOffset(
            metrics: metrics, column: column, current: workspace.scrollingOffset,
            snapToColumn: committedDockSwipe)
        if let window = column.node.mostRecentWindowRecursive, window.focusWindow() {
            workspace.lastScrollingFocusWindowId = window.windowId
            window.nativeFocus()
        }
        runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
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


/// A completed Dock swipe gets one adjacent-column fallback if an oversized
/// column remains nearest after the finger-following pan. Never skip a column,
/// reverse direction, or force a move when cancelled or at either strip edge.
/// In-flight progress and two-finger scroll are deliberately unaffected.
func settledDockSwipeColumn(in metrics: ScrollingWorkspaceMetrics, offset: CGFloat,
                            direction: CGFloat, startingColumnID: ObjectIdentifier?,
                            advanceIfStuck: Bool) -> ScrollingColumnMetric? {
    let nearest = nearestScrollingColumn(in: metrics, offset: offset, direction: direction)
    guard advanceIfStuck, let startingColumnID, direction != 0,
          let current = metrics.columns.firstIndex(where: { ObjectIdentifier($0.node) == startingColumnID }),
          let nearest, ObjectIdentifier(nearest.node) == startingColumnID else { return nearest }
    let next = current + (direction > 0 ? 1 : -1)
    guard metrics.columns.indices.contains(next) else { return nearest }
    return metrics.columns[next]
}

/// Preserve a physical scroll's final camera position. Only a committed
/// three-finger Dock swipe needs a deliberate column reveal/snap.
@MainActor
func scrollingPanReleaseOffset(metrics: ScrollingWorkspaceMetrics, column: ScrollingColumnMetric,
                               current: CGFloat, snapToColumn: Bool) -> CGFloat {
    let clamped = metrics.clampedOffset(current)
    return snapToColumn ? metrics.focusedOffset(for: column, current: clamped) : clamped
}
