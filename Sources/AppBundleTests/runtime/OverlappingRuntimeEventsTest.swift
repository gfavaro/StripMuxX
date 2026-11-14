@testable import AppBundle
import AppKit
import Common
import XCTest

/// Every suspension is controlled by a continuation. Seed and ordered actions are
/// included in assertion messages; these fixtures perform no native window work.
@MainActor
final class OverlappingRuntimeEventsTest: WorkspaceTestCase {
    private let seed: UInt64 = 0x574D_2026
    private var trace: [String] = []
    private func boundary(_ event: String, windows: [Window]? = nil, file: StaticString = #filePath, line: UInt = #line) {
        trace.append(event)
        XCTAssertEqual(runtime.modelInvariantViolations(expectedWindows: windows), [],
                       "seed=\(seed) events=\(trace)", file: file, line: line)
    }

    func testFixedSeedRapidSwitchesAndLateNativeCacheResults() {
        let a = Workspace.get(byName: "a"), b = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 44, parent: a.rootTilingContainer)
        var state = seed
        for index in 0..<128 {
            state = state &* 6364136223846793005 &+ 1
            let token = window.nativeStateObservationToken()
            _ = (state & 1 == 0 ? a : b).focusWorkspace()
            window.invalidateLastKnownNativeState()
            window.recordObservedNativeState(fullscreen: true, minimized: false, token: token)
            XCTAssertNil(window.lastKnownNativeFullscreen)
            boundary("switch \(index) stale native result rejected", windows: [window])
        }
    }
}
