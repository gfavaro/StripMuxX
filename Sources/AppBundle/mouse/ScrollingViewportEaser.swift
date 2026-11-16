import AppKit
import Common

/// Eases the windows of a scrolling gesture toward where the fingers have put the viewport.
/// Input still moves the real offset at once (focus, the minimap, saving and commands read
/// that); this only moves the offset the layout places windows by, one step per display frame,
/// so a flick delivered as a few large steps reaches the windows as many small ones and the
/// border has less to trail. Off while macOS Reduce Motion is on.
@MainActor
final class ScrollingViewportEaser {
    static let shared = ScrollingViewportEaser()
    private var workspace: Workspace?
    private var lastTick: CFTimeInterval = 0
    private var releaseFlagsWhenSettled = false

    /// Called by a pan step before it moves the real offset.
    func begin(_ workspace: Workspace, from current: CGFloat) {
        guard viewportEasingMilliseconds(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) > 0,
              !isUnitTest else { return }
        if workspace.scrollingRenderedOffset == nil { workspace.scrollingRenderedOffset = current }
        guard self.workspace !== workspace else { return }
        stop(finishing: true)
        self.workspace = workspace
        lastTick = CACurrentMediaTime()
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in self?.tick() }
    }

    /// The gesture ended: the windows keep easing, so its fast-write state is released only
    /// once they have arrived.
    func gestureEnded(_ workspace: Workspace) -> Bool {
        guard self.workspace === workspace, workspace.scrollingRenderedOffset != nil else { return false }
        releaseFlagsWhenSettled = true
        return true
    }

    private func tick() {
        guard let workspace, workspace.isVisible, let rendered = workspace.scrollingRenderedOffset else {
            return stop(finishing: true)
        }
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0.001), 0.05)
        lastTick = now
        let target = workspace.scrollingOffset
        let next = easedViewportOffset(rendered: rendered, target: target, elapsed: dt,
                                       smoothingMilliseconds: viewportEasingMilliseconds(reduceMotion: false))
        if abs(target - next) < 0.5 {
            workspace.scrollingRenderedOffset = nil
            runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
            return stop(finishing: false)
        }
        workspace.scrollingRenderedOffset = next
        runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
    }

    private func stop(finishing: Bool) {
        DisplayRefreshDriver.shared.remove(owner: self)
        guard let workspace else { return }
        self.workspace = nil
        if finishing, workspace.scrollingRenderedOffset != nil {
            workspace.scrollingRenderedOffset = nil
            runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
        }
        if releaseFlagsWhenSettled, !NativeScrollingPan.shared.isPanning(workspace) {
            workspace.scrollingGestureMotionActive = false
            workspace.scrollingGestureSessionID = nil
            runtime.native.tiling.relayoutVisibleScrolling(target: workspace)
        }
        releaseFlagsWhenSettled = false
    }
}

/// One step of exponential easing toward `target`. It never overshoots, and two half steps
/// land where one whole step does, so the result does not depend on the display's refresh rate.
func easedViewportOffset(rendered: CGFloat, target: CGFloat, elapsed: Double, smoothingMilliseconds: Int) -> CGFloat {
    guard smoothingMilliseconds > 0, elapsed > 0 else { return smoothingMilliseconds > 0 ? rendered : target }
    let tau = Double(smoothingMilliseconds) / 1000
    return rendered + (target - rendered) * CGFloat(1 - exp(-elapsed / tau))
}

/// How long windows take to catch up with the fingers, in milliseconds; none when the system asks
/// for reduced motion. About one flick step: long enough that a flick reads as motion and the
/// border can keep up, short enough that the windows do not feel behind the fingers.
func viewportEasingMilliseconds(reduceMotion: Bool) -> Int {
    reduceMotion ? 0 : 40
}
