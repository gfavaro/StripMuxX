@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class NativeEfficiencyTest: XCTestCase {

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
final class ScrollingRelayoutSelectionTest: WorkspaceTestCase {
    func testScopedRequestsDoNotTouchOtherDisplaysAndCoalesce() {
        let first = focus.workspace
        let second = Workspace.get(byName: "selection-test-second")
        var requests = ScrollingRelayoutSelection()
        requests.request(first)
        requests.request(first)
        let firstBatch = requests.drain()
        XCTAssertTrue(firstBatch.includes(first))
        XCTAssertFalse(firstBatch.includes(second))
        XCTAssertFalse(requests.drain().includes(first), "Drain removes completed work")

        requests.request(first)
        requests.request(second)
        let both = requests.drain()
        XCTAssertTrue(both.includes(first))
        XCTAssertTrue(both.includes(second))
    }

    func testUnscopedRefreshSupersedesAndResetsScopedRequests() {
        let first = focus.workspace
        let second = Workspace.get(byName: "selection-test-second")
        var requests = ScrollingRelayoutSelection()
        requests.request(first)
        requests.request(nil)
        requests.request(second)
        let all = requests.drain()
        XCTAssertTrue(all.includes(first))
        XCTAssertTrue(all.includes(second))
        XCTAssertFalse(requests.drain().includes(second))
    }
}
