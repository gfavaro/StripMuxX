@testable import AppBundle
import AppKit
import XCTest

/// StripMuxX must use the same renderer primitives as WinMuxX, not the
/// superseded single-panel stroke approximation.
@MainActor
final class NativeWindowBorderTest: XCTestCase {
    func testDefaultsMatchWinMuxX() {
        let options = WindowBordersConfig()
        XCTAssertTrue(options.enabled)
        XCTAssertEqual(options.width, 4)
        XCTAssertEqual(options.activeColor, "accent")
        XCTAssertEqual(options.inactiveColor, "#00000000")
        XCTAssertEqual(options.order, .below)
        XCTAssertEqual(options.excludeApps, [])
    }

    func testFocusedBorderUsesContinuousVectorGeometry() {
        let size = CGSize(width: 608, height: 408)
        let geometry = WindowBorderGeometry(size: size, radius: 12, width: 4, scale: 2)
        XCTAssertEqual(geometry.key.size, size)
        XCTAssertFalse(geometry.path.isEmpty)
    }
}
