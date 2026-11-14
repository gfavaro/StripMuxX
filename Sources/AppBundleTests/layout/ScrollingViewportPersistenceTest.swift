@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class ScrollingViewportPersistenceTest: WorkspaceTestCase {
    func testViewportSurvivesEncodingAndRestoringStrip() throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 73001, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 73002, parent: workspace.rootTilingContainer)
        first.scrollingColumnWidth = 0.6
        second.scrollingColumnWidth = 0.6
        workspace.scrollingOffset = 145

        let encoded = try JSONEncoder().encode(FrozenStrip(workspace))
        let restored = try JSONDecoder().decode(FrozenStrip.self, from: encoded)
        XCTAssertEqual(restored.scrollingOffset, 145)

        workspace.scrollingOffset = 0
        restoreStrip(restored, to: workspace, windowsById: [73001: first, 73002: second])
        XCTAssertEqual(workspace.scrollingOffset, 145)
        XCTAssertTrue(workspace.scrollingRestoredViewportPending)
    }

    func testOldSnapshotWithoutViewportStillDecodes() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 73003, parent: workspace.rootTilingContainer)
        let data = try JSONEncoder().encode(FrozenStrip(workspace))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "scrollingOffset")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(FrozenStrip.self, from: legacy)
        XCTAssertNil(restored.scrollingOffset)

        workspace.scrollingOffset = 99
        restoreStrip(restored, to: workspace, windowsById: [73003: window])
        XCTAssertEqual(workspace.scrollingOffset, 0)
        XCTAssertFalse(workspace.scrollingRestoredViewportPending)
    }
}
