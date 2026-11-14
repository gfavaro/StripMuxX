@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class SingleWindowGeometryTest: XCTestCase {
    func testScreenThresholdAndOrientation() {
        let available = Rect(topLeftX: 130, topLeftY: 40, width: 3000, height: 1001)
        for (width, height, limited) in [(1920.0, 1080.0, false), (2300, 1000, true), (2299, 1000, false), (3440, 1440, true), (5120, 1440, true), (1440, 3440, false)] {
            let result = singleWindowLimitedRect(available: available, screen: Rect(topLeftX: 0, topLeftY: 0, width: width, height: height), ratio: 1.5, minimumWidth: 0)
            XCTAssertEqual(result.width, limited ? 1500 : 3000)
            XCTAssertEqual(result.topLeftX, limited ? 880 : 130)
            XCTAssertEqual(result.height, 1001)
            XCTAssertEqual(result.topLeftY, 40)
        }
    }

    func testDisabledNarrowAreaAndMinimums() {
        let screen = Rect(topLeftX: 0, topLeftY: 0, width: 3440, height: 1440)
        let available = Rect(topLeftX: 100, topLeftY: 30, width: 3000, height: 1001)
        for (ratio, minimum, expected) in [(0.0, 0.0, 3000.0), (1.5, 1800, 1800), (1.5, 4000, 3000)] {
            XCTAssertEqual(singleWindowLimitedRect(available: available, screen: screen, ratio: ratio, minimumWidth: minimum).width, expected)
        }
        XCTAssertEqual(singleWindowLimitedRect(available: available.copy(\.width, 900), screen: screen, ratio: 1.5, minimumWidth: 0).width, 900)
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
