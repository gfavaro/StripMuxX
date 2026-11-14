@testable import AppBundle
import XCTest

@MainActor
private final class StripSwipeSpy: StripDockSwipeReceiver {
    var canStart = true
    var accept = true
    var began = 0
    var changes: [Double] = []
    var finishes = 0

    func dockSwipeMayStart() -> StripDockSwipeStart { canStart ? .started : .unavailable }
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> StripDockSwipeStart {
        began += 1
        return accept ? .started : .unavailable
    }
    func dockSwipeChanged(_ progress: Double, timestamp: Double) { changes.append(progress) }
    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) { finishes += 1 }
}

@MainActor
final class StripDockSwipeTrackerTest: XCTestCase {
    func testThreeFingerHorizontalSwipeIsClaimedAfterDirectionIsKnown() {
        var tracker = StripDockSwipeTracker(dockNeedsEnd: true)
        let spy = StripSwipeSpy()
        XCTAssertEqual(tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: spy), .hold)
        XCTAssertEqual(tracker.receive(phase: 2, progress: 0.02, endVelocity: 0, timestamp: 0.01, to: spy), .hold)
        XCTAssertEqual(tracker.receive(phase: 2, progress: -0.2, endVelocity: 0, timestamp: 0.03, to: spy), .swallow)
        XCTAssertEqual(tracker.receive(phase: 2, progress: -0.5, endVelocity: 0, timestamp: 0.08, to: spy), .swallow)
        XCTAssertEqual(spy.changes, [0.5])
        XCTAssertEqual(tracker.receive(phase: 4, progress: -0.5, endVelocity: 0, timestamp: 0.12, to: spy), .passWithoutMotion)
        XCTAssertEqual(spy.finishes, 1)
    }

    func testUnclaimedSwipesArePassedBackToTheDock() {
        var tracker = StripDockSwipeTracker(dockNeedsEnd: true)
        let spy = StripSwipeSpy()
        spy.canStart = false
        XCTAssertEqual(tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: spy), .pass)
        XCTAssertEqual(tracker.receive(phase: 2, progress: 0.3, endVelocity: 0, timestamp: 0.05, to: spy), .pass)
        XCTAssertEqual(spy.began, 0)
    }

    func testUndecidedSwipeCanReturnToMacOS() {
        var tracker = StripDockSwipeTracker(dockNeedsEnd: true)
        let spy = StripSwipeSpy()
        spy.accept = false
        XCTAssertEqual(tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: spy), .hold)
        XCTAssertEqual(tracker.receive(phase: 2, progress: 0.2, endVelocity: 0, timestamp: 0.05, to: spy), .replayHeldThenPass)
        XCTAssertEqual(tracker.receive(phase: 4, progress: 0.2, endVelocity: 0, timestamp: 0.1, to: spy), .pass)
    }

    func testCancelDoesNotCommitOrLeakState() {
        var tracker = StripDockSwipeTracker(dockNeedsEnd: true)
        let spy = StripSwipeSpy()
        _ = tracker.receive(phase: 1, progress: 0, endVelocity: 0, timestamp: 0, to: spy)
        _ = tracker.receive(phase: 2, progress: 0.4, endVelocity: 0, timestamp: 0.1, to: spy)
        XCTAssertEqual(tracker.receive(phase: 8, progress: 0, endVelocity: 0, timestamp: 0.2, to: spy), .swallow)
        XCTAssertEqual(spy.finishes, 1)
        XCTAssertFalse(tracker.ownsGesture)
    }
}
