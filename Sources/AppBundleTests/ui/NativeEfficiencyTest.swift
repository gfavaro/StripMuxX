@testable import AppBundle
import AppKit
import XCTest

private actor EfficiencyGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
    }
}

@MainActor
final class NativeEfficiencyTest: XCTestCase {
    func testNativeNotificationBurstProducesOneScanAndCanRestartAfterIdle() async {
        let gate = EfficiencyGate()
        let scheduler = NativeWindowRefreshScheduler(sleep: { await gate.wait() })
        let first = expectation(description: "one scan")
        var scans = 0
        for _ in 0..<1_000 { scheduler.request { scans += 1; first.fulfill() } }
        XCTAssertEqual(scans, 0)
        await gate.open()
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(scans, 1)
        let next = expectation(description: "next scan")
        scheduler.request { scans += 1; next.fulfill() }
        await fulfillment(of: [next], timeout: 2)
        XCTAssertEqual(scans, 2)
    }

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
