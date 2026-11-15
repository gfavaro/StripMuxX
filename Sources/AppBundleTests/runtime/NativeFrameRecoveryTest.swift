@testable import AppBundle
import XCTest

final class NativeFrameRecoveryTest: XCTestCase {
    private let tile = Rect(topLeftX: 100, topLeftY: 50, width: 800, height: 600)

    func testRestingAllowsLargerWindowsAndRowSizedOnes() {
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 100, y: 50, width: 800, height: 600), tile: tile))
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 101, y: 52, width: 950, height: 600), tile: tile), "Cannot shrink to the tile")
        XCTAssertTrue(windowRestsOnTile(CGRect(x: 100, y: 50, width: 790, height: 584), tile: tile), "Whole rows and columns")
        XCTAssertFalse(windowRestsOnTile(CGRect(x: 300, y: 50, width: 800, height: 600), tile: tile), "Moved")
        XCTAssertFalse(windowRestsOnTile(CGRect(x: 100, y: 50, width: 500, height: 600), tile: tile), "Shrunk")
    }

    func testBudgetStopsAFightAndRefillsWithTimeOrANewTile() {
        var budget = FrameRecoveryBudget()
        let start = ContinuousClock.now
        XCTAssertEqual((0..<5).map { budget.shouldReapply(tile: tile, resting: false, now: start + .seconds($0)) }, [true, true, true, false, false],
                       "An app that keeps moving its window is left alone after three tries")
        XCTAssertFalse(budget.shouldReapply(tile: tile, resting: true, now: start + .seconds(5)), "Resting needs no put-back")
        XCTAssertFalse(budget.shouldReapply(tile: tile, resting: false, now: start + .seconds(6)), "and does not refill it")
        XCTAssertTrue(budget.shouldReapply(tile: tile, resting: false, now: start + .seconds(10)), "A try older than the window expires")
        var moved = tile
        moved.topLeftX += 400
        XCTAssertTrue(budget.shouldReapply(tile: moved, resting: false, now: start + .seconds(11)), "A new tile refills it")
    }

    func testAnAppThatMovesItsWindowNowAndThenIsAlwaysPutBack() {
        var budget = FrameRecoveryBudget()
        let start = ContinuousClock.now
        XCTAssertTrue((0..<10).allSatisfy { budget.shouldReapply(tile: tile, resting: false, now: start + .seconds(4 * $0)) })
    }
}

@MainActor
final class NativeFrameRecoveryEligibilityTest: XCTestCase {
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testParkedColumnsAreNotPutBackButVisibleAndOnlyTiledOnesAre() async throws {
        setUpWorkspacesForTests()
        let workspace = focus.workspace
        let windows = (0..<4).map { TestWindow.new(id: UInt32(9800 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.5 }
        let floating = TestWindow.new(id: 9810, parent: workspace)
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace()
        XCTAssertTrue(frameRecoveryApplies(to: windows[0]), "A column in view is put back")
        XCTAssertTrue(windows[3].isConcealedByScrolling, "Four half-width columns overflow the display")
        XCTAssertFalse(frameRecoveryApplies(to: windows[3]), "A parked column is left where macOS keeps it")
        XCTAssertFalse(frameRecoveryApplies(to: floating), "Floating windows are never put back")
    }
}
