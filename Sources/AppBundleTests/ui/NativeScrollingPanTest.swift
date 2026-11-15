@testable import AppBundle
import AppKit
import Common
@testable import NativeSpaces
import XCTest

@MainActor
final class NativeScrollingPanTest: WorkspaceTestCase {
    /// An observed native desktop showing on the test display.
    private func nativeDesktop() -> Workspace {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let monitor = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "display-a", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([monitor])
        var inventory = NativeWorkspaceInventory()
        _ = inventory.publish(NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "1",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0)])], windows: [], readMilliseconds: 0, capturedAt: .now),
            for: inventory.invalidate())
        runtime.native.layouts.reconcile(inventory, displays: [monitor])
        return runtime.native.layouts.retainedByUUID["desktop-a"]!
    }

    private func fixture() -> (Workspace, [TestWindow]) {
        let workspace = nativeDesktop()
        let windows = (0..<4).map { TestWindow.new(id: UInt32(97000 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        _ = windows[0].focusWindow()
        return (workspace, windows)
    }

    private func scroll(_ dx: CGFloat, dy: CGFloat = 0, option: Bool = true, continuous: Bool = true,
                        phase: Int64 = 2, momentum: Int64 = 0, at point: CGPoint) -> NativeScrollingPan.Scroll {
        .init(deltaX: dx, deltaY: dy, isContinuous: continuous, optionOnly: option, phase: phase,
              momentumPhase: momentum, point: point)
    }

    func testOptionShiftGestureResizesFocusedColumnWithoutPanning() {
        let (workspace, windows) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        let before = workspace.scrollingMetrics.columns[0].width
        let offset = workspace.scrollingOffset
        let start = NativeScrollingPan.Scroll(deltaX: 90, deltaY: 0, isContinuous: true,
            optionOnly: false, resizeOnly: true, phase: 1, momentumPhase: 0, point: point)
        XCTAssertTrue(pan.handle(start))
        XCTAssertEqual(workspace.scrollingOffset, offset)
        let after = workspace.scrollingMetrics.columns[0].width
        XCTAssertGreaterThan(after, before)
        XCTAssertTrue(windows[0] === focus.windowOrNil)
        XCTAssertTrue(pan.handle(.init(deltaX: 0, deltaY: 0, isContinuous: true,
            optionOnly: false, resizeOnly: true, phase: 4, momentumPhase: 0, point: point)))
        XCTAssertFalse(pan.isPanning)
        XCTAssertEqual(workspace.scrollingMetrics.columns[0].width, after, accuracy: 1)
    }

    func testMomentumAfterAResizeLiftStaysWithTheGestureAndChangesNothing() {
        let (workspace, _) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        func resize(_ dx: CGFloat, phase: Int64, momentum: Int64 = 0, keys: Bool = true) -> NativeScrollingPan.Scroll {
            .init(deltaX: dx, deltaY: 0, isContinuous: true, optionOnly: false, resizeOnly: keys,
                  phase: phase, momentumPhase: momentum, point: point)
        }
        XCTAssertTrue(pan.handle(resize(90, phase: 1)))
        XCTAssertTrue(pan.handle(resize(40, phase: 2)))
        XCTAssertTrue(pan.handle(resize(0, phase: 4)), "Lifting the fingers ends the resize")
        let width = workspace.scrollingMetrics.columns[0].width
        let offset = workspace.scrollingOffset
        // macOS then streams momentum, with or without the modifiers still held.
        for (momentum, keys) in [(Int64(1), true), (2, true), (2, false), (2, false), (3, false)] {
            XCTAssertTrue(pan.handle(resize(60, phase: 0, momentum: momentum, keys: keys)),
                          "Momentum of the resize must not reach the app under the pointer")
        }
        XCTAssertEqual(workspace.scrollingMetrics.columns[0].width, width, accuracy: 0.5, "Momentum never resizes")
        XCTAssertEqual(workspace.scrollingOffset, offset, "Momentum never pans")
        XCTAssertFalse(pan.isPanning)
        XCTAssertFalse(pan.handle(scroll(30, option: false, phase: 1, at: point)), "A new plain scroll reaches the app")
    }

    func testFiveThousandRandomScrollEventsKeepEveryInvariant() {
        let (workspace, windows) = fixture()
        windows[2].scrollingColumnWidth = 0.2
        let other = Workspace.get(byName: "not-showing")
        let bystander = TestWindow.new(id: 97900, parent: other.rootTilingContainer)
        bystander.scrollingColumnWidth = 0.4
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let phases: [Int64] = [0, 1, 2, 2, 2, 4]
        for step in 0..<5_000 {
            let keys = next(4) // 0 plain, 1 Option, 2 Option+Shift, 3 Option (again)
            let momentum: Int64 = next(5) == 0 ? Int64([1, 2, 2, 3][next(4)]) : 0
            let dx = CGFloat(next(5) == 0 ? 0 : next(401) - 200)
            let dy = CGFloat(next(6) == 0 ? next(201) - 100 : 0)
            let event = NativeScrollingPan.Scroll(deltaX: dx, deltaY: dy, isContinuous: next(10) != 0,
                optionOnly: keys == 1 || keys == 3, resizeOnly: keys == 2,
                phase: momentum == 0 ? phases[next(phases.count)] : 0, momentumPhase: momentum, point: point)
            let wasIdle = !pan.isPanning
            let focusBefore = focus.windowOrNil
            // Part of a resize gesture: one already resizing, or one this event starts.
            let inResize = pan.isPanning && pan.lastDecision == "resizing column"
            let consumed = pan.handle(event)
            let resizing = inResize || (wasIdle && pan.isPanning && pan.lastDecision == "resizing column")
            if wasIdle, keys == 0, momentum == 0, event.phase == 1 {
                XCTAssertFalse(consumed, "step \(step): a plain new scroll belongs to the app")
            }
            if resizing, consumed { XCTAssertTrue(focus.windowOrNil === focusBefore, "step \(step): resizing never moves focus") }
            let metrics = workspace.scrollingMetrics
            // The stored offset may trail a resize until the next layout clamps it; what
            // windows are placed by is the geometry's clamped offset, which must be in range.
            XCTAssertTrue(metrics.offsetRange.contains(metrics.geometry.clampedOffset), "step \(step): placed viewport in range")
            let swallowedMomentum = wasIdle && !pan.isPanning && consumed
            if !resizing, consumed, !swallowedMomentum, abs(metrics.clampedOffset(workspace.scrollingOffset) - workspace.scrollingOffset) >= 0.5 {
                XCTFail("step \(step): a pan left the stored viewport out of range")
            }
            for column in metrics.columns {
                XCTAssertGreaterThan(column.width, 0, "step \(step)")
                XCTAssertLessThanOrEqual(column.width, metrics.areaWidth + 0.5, "step \(step): width within the display")
            }
            XCTAssertEqual(bystander.scrollingColumnWidth, 0.4, "step \(step): another desktop is never touched")
            if step % 250 == 249 { pan.cancel() }
        }
        pan.cancel()
        XCTAssertFalse(pan.isPanning)
    }

    func testOnlyOptionHorizontalTrackpadScrollOverAScrollingDesktopPans() {
        let (workspace, _) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        XCTAssertFalse(pan.handle(scroll(-80, option: false, at: point)), "Plain scroll stays with the app")
        XCTAssertFalse(pan.handle(scroll(-5, dy: -40, at: point)), "Vertical scroll stays with the app")
        XCTAssertFalse(pan.handle(scroll(-80, continuous: false, at: point)), "Mouse wheels stay with the app")
        let before = workspace.scrollingOffset
        XCTAssertTrue(pan.handle(scroll(-120, phase: 1, at: point)))
        XCTAssertGreaterThan(workspace.scrollingOffset, before, "Fingers moving left reveal columns to the right")
        XCTAssertTrue(workspace.scrollingGestureMotionActive)
        let panned = workspace.scrollingOffset
        XCTAssertTrue(pan.handle(scroll(0, phase: 4, at: point)))
        XCTAssertTrue(workspace.scrollingGestureMotionActive, "Lifting the fingers waits for macOS's momentum")
        XCTAssertTrue(pan.handle(scroll(-60, option: false, phase: 0, momentum: 2, at: point)), "Momentum belongs to the pan")
        XCTAssertGreaterThan(workspace.scrollingOffset, panned, "Momentum keeps moving the desktop")
        XCTAssertTrue(pan.handle(scroll(0, option: false, phase: 0, momentum: 3, at: point)))
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertEqual(pan.lastDecision, "panning")
        XCTAssertFalse(pan.isPanning)
        XCTAssertTrue(nativePanIgnoresNotification(kAXWindowMovedNotification as String), "Its own moves keep the permits")
        XCTAssertFalse(nativePanIgnoresNotification(kAXWindowMiniaturizedNotification as String), "Ownership changes still revoke")
        let metrics = workspace.scrollingMetrics
        XCTAssertTrue(metrics.offsetRange.contains(workspace.scrollingOffset),
            "The physical pan ends within the strip without snapping to a column")
    }

    func testPhysicalScrollReleaseKeepsCameraWhileDockCompletionCanRevealColumn() {
        let (workspace, _) = fixture()
        let metrics = workspace.scrollingMetrics
        let target = metrics.columns[1]
        let betweenColumns = metrics.clampedOffset(target.start - metrics.areaWidth * 0.3)
        XCTAssertEqual(scrollingPanReleaseOffset(metrics: metrics, column: target,
            current: betweenColumns, snapToColumn: false), betweenColumns, accuracy: 0.001)
        XCTAssertEqual(scrollingPanReleaseOffset(metrics: metrics, column: target,
            current: betweenColumns, snapToColumn: true),
            metrics.focusedOffset(for: target, current: betweenColumns), accuracy: 0.001)
        XCTAssertEqual(scrollingPanReleaseOffset(metrics: metrics, column: target,
            current: -1000, snapToColumn: false), metrics.offsetRange.lowerBound, accuracy: 0.001)
    }

    func testPhysicalPanDoesNotSnapBackOnRelease() {
        let (workspace, windows) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        XCTAssertTrue(pan.handle(scroll(-177, phase: 1, at: point)))
        let draggedOffset = workspace.scrollingOffset
        XCTAssertGreaterThan(draggedOffset, 0)
        XCTAssertTrue(pan.handle(scroll(0, option: false, phase: 0, momentum: 3, at: point)))
        XCTAssertEqual(workspace.scrollingOffset, draggedOffset, accuracy: 0.001,
                       "Releasing a physical trackpad pan should never reposition its viewport")
        XCTAssertFalse(pan.isPanning)
        XCTAssertNotNil(focus.windowOrNil)
        XCTAssertTrue(windows.contains { $0 === focus.windowOrNil })
    }

    func testTouchEndAndMomentumHandoffKeepContinuousViewport() {
        let (workspace, _) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        XCTAssertTrue(pan.handle(scroll(-135, phase: 1, at: point)))
        let touched = workspace.scrollingOffset
        XCTAssertTrue(pan.handle(scroll(0, phase: 4, at: point)))
        XCTAssertTrue(pan.isPanning)
        XCTAssertEqual(workspace.scrollingOffset, touched, accuracy: 0.001)
        XCTAssertTrue(pan.handle(scroll(-45, option: false, phase: 0, momentum: 2, at: point)))
        let coasted = workspace.scrollingOffset
        XCTAssertGreaterThan(coasted, touched)
        XCTAssertTrue(pan.handle(scroll(0, option: false, phase: 0, momentum: 3, at: point)))
        XCTAssertFalse(pan.isPanning)
        XCTAssertEqual(workspace.scrollingOffset, coasted, accuracy: 0.001)
    }

    func testANewPlainScrollEndsThePanAndReachesTheApp() {
        let (workspace, _) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        XCTAssertTrue(pan.handle(scroll(-120, phase: 1, at: point)))
        XCTAssertTrue(pan.isPanning)
        XCTAssertFalse(pan.handle(scroll(0, dy: -30, option: false, phase: 1, at: point)), "A new vertical scroll goes to the app")
        XCTAssertFalse(pan.isPanning)
        XCTAssertTrue(nativePanIgnoresNotification(kAXFocusedWindowChangedNotification as String), "Its own raises keep the permits")
        XCTAssertTrue(NativeCommandPolicy.runsOutsideNativeTilingFence(try! XCTUnwrap(parseCommand("mode main").unwrap().0)),
            "mode switches bindings even while tiling is paused")
    }

    func testUnrelatedScrollCancelsWithoutStealingFocus() {
        let (workspace, windows) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        _ = windows[0].focusWindow()
        XCTAssertTrue(pan.handle(scroll(-160, phase: 1, at: point)))
        let moved = workspace.scrollingOffset
        XCTAssertFalse(pan.handle(scroll(0, dy: -30, option: false, phase: 1, at: point)))
        XCTAssertEqual(workspace.scrollingOffset, moved, accuracy: 1)
        XCTAssertTrue(focus.windowOrNil === windows[0])
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertNil(workspace.scrollingGestureSessionID)
    }

    func testNativeDesktopSwitchCancelsGestureWithoutConsumingScroll() {
        let (workspace, windows) = fixture()
        let pan = NativeScrollingPan()
        let point = workspace.workspaceMonitor.rect.center
        _ = windows[0].focusWindow()
        XCTAssertTrue(pan.handle(scroll(-150, phase: 1, at: point)))
        workspace.scrollingSessionEpoch &+= 1
        XCTAssertFalse(pan.handle(scroll(-60, phase: 2, at: point)))
        XCTAssertFalse(pan.isPanning)
        XCTAssertFalse(workspace.scrollingGestureMotionActive)
        XCTAssertTrue(focus.windowOrNil === windows[0])
        XCTAssertEqual(pan.lastDecision, "gesture cancelled: desktop or session changed")
    }

    func testEdgePreviewHasSafeBounds() {
        XCTAssertEqual(parseConfig("[scrolling]\nedge-preview = 0").config.scrolling.edgePreview, 0)
        XCTAssertEqual(parseConfig("[scrolling]\nedge-preview = 40").config.scrolling.edgePreview, 40)
        XCTAssertFalse(parseConfig("[scrolling]\nedge-preview = 41").errors.isEmpty)
        XCTAssertFalse(parseConfig("[scrolling]\nedge-preview = -1").errors.isEmpty)
    }

    func testExperimentalThreeFingerSwipeConfigDefaultsOffAndCanBeEnabled() {
        XCTAssertFalse(parseConfig("[scrolling]\ngesture-enabled = true").config.scrolling.threeFingerSwipe)
        let enabled = parseConfig("[scrolling]\nthree-finger-swipe = true")
        XCTAssertTrue(enabled.errors.isEmpty, "\(enabled.errors)")
        XCTAssertTrue(enabled.config.scrolling.threeFingerSwipe)
    }

    func testDockCompletionAssistsWideColumnButNeverSkips() {
        let (workspace, windows) = fixture()
        windows.forEach { $0.scrollingColumnWidth = 1.0 }
        let metrics = workspace.scrollingMetrics
        let first = metrics.columns[0]
        let start = ObjectIdentifier(first.node)
        let offset = metrics.clampedOffset(0.25 * metrics.areaWidth)
        XCTAssertTrue(nearestScrollingColumn(in: metrics, offset: offset, direction: 1)?.node === first.node)
        let chosen = settledDockSwipeColumn(in: metrics, offset: offset, direction: 1,
                                            startingColumnID: start, advanceIfStuck: true)
        XCTAssertTrue(chosen?.node === metrics.columns[1].node)
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: offset, direction: 1,
            startingColumnID: start, advanceIfStuck: false)?.node === first.node)
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: offset, direction: 1,
            startingColumnID: nil, advanceIfStuck: true)?.node === first.node)
    }

    func testDockCompletionDoesNotAdvanceWhenViewportAlreadyMovedToAnotherColumn() {
        let (workspace, windows) = fixture()
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        let metrics = workspace.scrollingMetrics
        let start = ObjectIdentifier(metrics.columns[0].node)
        let targetOffset = metrics.centeredOffset(for: metrics.columns[1])
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: targetOffset, direction: 1,
            startingColumnID: start, advanceIfStuck: true)?.node === metrics.columns[1].node)
    }

    func testDockCompletionRespectsStripEdgesAndReverseDirection() {
        let (workspace, _) = fixture()
        let metrics = workspace.scrollingMetrics
        let first = ObjectIdentifier(metrics.columns[0].node)
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: 0, direction: -1,
            startingColumnID: first, advanceIfStuck: true)?.node === metrics.columns[0].node)
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: 0, direction: 0,
            startingColumnID: first, advanceIfStuck: true)?.node === metrics.columns[0].node)
        let last = metrics.columns[metrics.columns.count - 1]
        let end = metrics.offsetRange.upperBound
        XCTAssertTrue(settledDockSwipeColumn(in: metrics, offset: end, direction: 1,
            startingColumnID: ObjectIdentifier(last.node), advanceIfStuck: true)?.node === last.node)
    }

    func testCommittedWideSwipeSelectsOnlyImmediateNeighborInLargeStrip() {
        let workspace = nativeDesktop()
        let windows = (0..<50).map {
            TestWindow.new(id: UInt32(98000 + $0), parent: workspace.rootTilingContainer)
        }
        windows.forEach { $0.scrollingColumnFixedWidth = 2400 }
        let metrics = workspace.scrollingMetrics
        XCTAssertEqual(metrics.columns.count, 50)
        let pivot = metrics.columns[24]
        let targetOffset = metrics.centeredOffset(for: pivot)
        let selected = settledDockSwipeColumn(in: metrics, offset: targetOffset, direction: 1,
            startingColumnID: ObjectIdentifier(pivot.node), advanceIfStuck: true)
        XCTAssertTrue(selected?.node === metrics.columns[25].node)
        let backwards = settledDockSwipeColumn(in: metrics, offset: targetOffset, direction: -1,
            startingColumnID: ObjectIdentifier(pivot.node), advanceIfStuck: true)
        XCTAssertTrue(backwards?.node === metrics.columns[23].node)
    }

    func testADisplayShowingAFullscreenSpaceHasNoDesktopAndCreatesNone() {
        let desktop = nativeDesktop()
        var inventory = NativeWorkspaceInventory()
        _ = inventory.publish(NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "9",
            spaces: [NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4)])],
            windows: [], readMilliseconds: 0, capturedAt: .now), for: inventory.invalidate())
        runtime.native.layouts.reconcile(inventory, displays: [desktop.workspaceMonitor])
        let before = Workspace.all.count
        XCTAssertNil(nativeActiveDesktop(on: desktop.workspaceMonitor))
        XCTAssertFalse(NativeScrollingPan().handle(scroll(-120, at: desktop.workspaceMonitor.rect.center)))
        XCTAssertEqual(Workspace.all.count, before, "No virtual workspace is created for the display")
    }
}
