@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class SingleWindowGeometryTest: XCTestCase {
    func testRatioLimitsTheWidthOnAnyDisplayShape() {
        let available = Rect(topLeftX: 130, topLeftY: 40, width: 3000, height: 1001)
        for (ratio, expected) in [(1.5, 1500.0), (1.0, 1000), (2.5, 2500), (3.0, 3000), (6.0, 3000)] {
            let result = singleWindowLimitedRect(available: available, ratio: ratio, minimumWidth: 0)
            XCTAssertEqual(result.width, expected, "ratio \(ratio)")
            XCTAssertEqual(result.topLeftX, 130 + (3000 - expected) / 2, "centered")
            XCTAssertEqual(result.height, 1001)
            XCTAssertEqual(result.topLeftY, 40)
        }
    }

    func testDisabledNarrowAreaAndMinimums() {
        let available = Rect(topLeftX: 100, topLeftY: 30, width: 3000, height: 1001)
        for (ratio, minimum, expected) in [(0.0, 0.0, 3000.0), (1.5, 1800, 1800), (1.5, 4000, 3000)] {
            XCTAssertEqual(singleWindowLimitedRect(available: available, ratio: ratio, minimumWidth: minimum).width, expected)
        }
        XCTAssertEqual(singleWindowLimitedRect(available: available.copy(\.width, 900), ratio: 1.5, minimumWidth: 0).width, 900)
    }

    func testAlignmentAndParsing() {
        let available = Rect(topLeftX: 150, topLeftY: 20, width: 3000, height: 1001)
        for (alignment, expectedX) in [(SingleWindowAlignment.left, 150.0), (.center, 900.0), (.right, 1650.0)] {
            let rect = alignedSingleWindowRect(available: available, width: 1500, minimumWidth: 0, alignment: alignment)
            XCTAssertEqual(rect.topLeftX, expectedX)
            XCTAssertEqual(rect.height, available.height)
            let parsed = parseConfig("single-window-alignment = '\(alignment.rawValue)'")
            XCTAssertTrue(parsed.errors.isEmpty)
            XCTAssertEqual(parsed.config.singleWindowAlignment, alignment)
        }
        XCTAssertFalse(parseConfig("single-window-alignment = 'bottom'").errors.isEmpty)
    }

}
