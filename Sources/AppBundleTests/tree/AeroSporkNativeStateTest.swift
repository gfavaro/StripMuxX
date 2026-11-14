@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class AeroSporkNativeStateTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testOneActualTimeoutSkipsQueuedReadsButOtherAppsAndNextPassStillRun() {
        let budget = AXReadBudget()
        var reads = 0
        let first: Result<Int, AXReadFailure> = budget.read(pid: 10) { reads += 1; return .failure(AXReadFailure(code: .cannotComplete)) }
        XCTAssertThrowsError(try first.get())
        let skipped: Result<Int, AXReadFailure> = budget.read(pid: 10) { reads += 1; return .success(1) }
        XCTAssertThrowsError(try skipped.get())
        let other = budget.read(pid: 11) { reads += 1; return .success(2) }
        XCTAssertEqual(try other.get(), 2)
        let next = AXReadBudget().read(pid: 10) { reads += 1; return .success(3) }
        XCTAssertEqual(try next.get(), 3)
        XCTAssertEqual(reads, 3)
        let unavailable: Result<Int?, AXReadFailure> = budget.read(pid: 12) { .success(nil) }
        XCTAssertNil(try unavailable.get())
        XCTAssertTrue(budget.permits(12), "An absent attribute is not an app timeout")
    }
}

private final class UnknownFocusProbeApp: AbstractApp {
    let pid: Int32 = -8107
    let rawAppBundleId: String? = "test.unknown-focus"
    let name: String? = "Unknown focus probe"
    let execPath: String? = nil
    let bundlePath: String? = nil
    @MainActor func getFocusedWindow() async throws -> Window? { throw NativeFocusUnknown() }
}
