@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class NativeWindowBorderTest: XCTestCase {
    func testBorderFrameExpandsOutsideTheWindowWithoutChangingWindowGeometry() {
        let window = CGRect(x: 100, y: 200, width: 600, height: 400)
        let border = NativeWindowBorder.panelFrame(for: window, mainDisplayHeight: 1200)
        XCTAssertEqual(border.minX, 96)
        XCTAssertEqual(border.minY, 596)
        XCTAssertEqual(border.width, 608)
        XCTAssertEqual(border.height, 408)
        XCTAssertEqual(window, CGRect(x: 100, y: 200, width: 600, height: 400))
    }

    func testBorderCoordinateConversionHandlesSecondaryDisplayAtNegativeCoordinates() {
        let window = CGRect(x: -1200, y: -150, width: 500, height: 350)
        let border = NativeWindowBorder.panelFrame(for: window, mainDisplayHeight: 1080)
        XCTAssertEqual(border.minX, -1204)
        XCTAssertEqual(border.minY, 876)
        XCTAssertEqual(border.size.width, 508)
        XCTAssertEqual(border.size.height, 358)
    }
}
