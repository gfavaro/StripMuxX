@testable import AppBundle
import AppKit
import XCTest

/// Isolated geometry tests that do not require AX, running applications or native Spaces.
final class ScrollingGeometryTest: XCTestCase {
    private func makeInput(
        offset: CGFloat = 0,
        widths: [CGFloat] = [0.5, 0.5, 0.5],
        leftWall: Bool = false,
        rightWall: Bool = false,
        preview: CGFloat = 25,
        minimum: CGFloat = 0,
        sheetOffset: CGFloat? = nil
    ) -> ScrollingWorkspaceGeometryInput {
        .init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            offset: offset,
            columns: widths.map { .init(preferredWidth: $0, minimumWidth: minimum) },
            horizontalGap: 0, outerLeft: 0, outerRight: 0,
            leftWall: leftWall, rightWall: rightWall, preview: preview,
            sheetOffset: sheetOffset
        )
    }

    func testEmptyStripHasZeroRange() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(widths: []))
        XCTAssertTrue(result.columns.isEmpty)
        XCTAssertEqual(result.clampedOffset, 0)
        XCTAssertEqual(result.offsetRange.lowerBound, 0)
        XCTAssertEqual(result.offsetRange.upperBound, 0)
    }

    func testThreeColumnsScrollWithinLogicalRangeAndParkOutsideViewport() {
        let first = calculateScrollingWorkspaceGeometry(makeInput())
        XCTAssertEqual(first.area.minX, 25)
        XCTAssertEqual(first.area.width, 950)
        XCTAssertEqual(first.columns.map(\.spanWidth), [475, 475, 475])
        XCTAssertEqual(first.offsetRange.lowerBound, 0)
        XCTAssertEqual(first.offsetRange.upperBound, 475)
        XCTAssertEqual(first.columns[2].visibility, .rightPreview)
        XCTAssertEqual(first.columns[2].physicalFrame.minX, 975)

        let last = calculateScrollingWorkspaceGeometry(makeInput(offset: 10_000))
        XCTAssertEqual(last.clampedOffset, 475)
        XCTAssertEqual(last.columns[0].visibility, .leftPreview)
        XCTAssertEqual(last.columns[0].physicalFrame.maxX, 25)
        XCTAssertEqual(last.columns[2].visibility, .visible)
    }

    func testAdjacentDisplayWallKeepsParkedWindowOnItsOwnDisplay() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(rightWall: true))
        XCTAssertEqual(result.columns[2].visibility, .parkedRight)
        XCTAssertEqual(result.columns[2].physicalFrame.maxX, 1000)
        XCTAssertGreaterThanOrEqual(result.columns[2].physicalFrame.minX, 0)
    }

    func testNarrowStripCentersWithoutScrolling() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: 100, widths: [0.3]))
        XCTAssertEqual(result.columns.count, 1)
        XCTAssertEqual(result.clampedOffset, 0)
        XCTAssertEqual(result.columns[0].logicalFrame.width, result.area.width)
    }

    func testMinimumWindowWidthOverridesPreferredShare() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(widths: [0.2, 0.2], minimum: 600))
        XCTAssertEqual(result.columns.map(\.spanWidth), [600, 600])
        XCTAssertEqual(result.offsetRange.upperBound, 250)
    }

    func testNonfiniteInputDoesNotPoisonGeometry() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: .nan, widths: [.nan, .infinity], preview: .nan))
        XCTAssertTrue(result.clampedOffset.isFinite)
        XCTAssertTrue(result.columns.allSatisfy { $0.physicalFrame.origin.x.isFinite && $0.physicalFrame.size.width.isFinite })
    }

    func testSheetOffsetExtendsAllowedRangeTemporarily() {
        let result = calculateScrollingWorkspaceGeometry(makeInput(offset: -80, sheetOffset: -80))
        XCTAssertEqual(result.offsetRange.lowerBound, -80)
        XCTAssertEqual(result.clampedOffset, -80)
        let settled = calculateScrollingWorkspaceGeometry(makeInput(offset: -80))
        XCTAssertEqual(settled.clampedOffset, 0)
    }
}
