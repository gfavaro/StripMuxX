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


    func testRestoredViewportIsNotOverriddenByInitialFocusLayout() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 73011, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 73012, parent: workspace.rootTilingContainer)
        first.scrollingColumnWidth = 0.6
        second.scrollingColumnWidth = 0.6
        _ = first.focusWindow()
        workspace.scrollingOffset = 120
        let record = FrozenStrip(workspace)

        workspace.scrollingOffset = 0
        workspace.lastScrollingFocusWindowId = nil
        restoreStrip(record, to: workspace, windowsById: [73011: first, 73012: second])
        XCTAssertTrue(workspace.scrollingRestoredViewportPending)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(workspace.scrollingOffset, 120, accuracy: 1)
        XCTAssertFalse(workspace.scrollingRestoredViewportPending)
        XCTAssertEqual(workspace.lastScrollingFocusWindowId, first.windowId)
    }

    func testOnlyAWindowFloatedOnPurposeFloatsAgainAfterRestore() throws {
        let workspace = focus.workspace
        let auto = TestWindow.new(id: 73031, parent: workspace)
        let kept = TestWindow.new(id: 73032, parent: workspace)
        kept.keptFloating = true
        let record = try JSONDecoder().decode(FrozenStrip.self, from: JSONEncoder().encode(FrozenStrip(workspace)))
        XCTAssertEqual(record.floating.count, 2)

        // After a restart both open on the strip at their own size, as adoption places them.
        let own = Rect(topLeftX: 200, topLeftY: 100, width: 500, height: 300)
        kept.keptFloating = false
        joinStripAtOwnSize(auto, on: workspace, rect: own)
        joinStripAtOwnSize(kept, on: workspace, rect: own)
        restoreStrip(record, to: workspace, windowsById: [73031: auto, 73032: kept])

        XCTAssertFalse(auto.isFloating)
        XCTAssertEqual(auto.freeSizeRect, own)
        XCTAssertTrue(kept.isFloating)
        XCTAssertTrue(kept.keptFloating)
    }

    func testFreeSizeFrameSurvivesSnapshotAndRestore() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 73021, parent: workspace.rootTilingContainer)
        window.freeSizeRect = Rect(topLeftX: 180, topLeftY: 90, width: 740, height: 390)
        window.freeSizePreviousColumnWidth = 0.5
        window.scrollingColumnFixedWidth = 740
        let data = try JSONEncoder().encode(FrozenStrip(workspace))
        let record = try JSONDecoder().decode(FrozenStrip.self, from: data)

        window.freeSizeRect = nil
        window.scrollingColumnFixedWidth = nil
        restoreStrip(record, to: workspace, windowsById: [73021: window])

        XCTAssertEqual(window.freeSizeRect?.width, 740)
        XCTAssertEqual(window.freeSizeRect?.height, 390)
        XCTAssertEqual(window.freeSizeRect?.topLeftY, 90)
        XCTAssertEqual(window.scrollingColumnFixedWidth, 740)
        XCTAssertEqual(window.freeSizePreviousColumnWidth, 0.5)
    }

    func testOldWindowSnapshotWithoutFreeSizeFieldsRestoresAsTiled() throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 73022, parent: workspace.rootTilingContainer)
        let data = try JSONEncoder().encode(FrozenStrip(workspace))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var root = try XCTUnwrap(object["root"] as? [String: Any])
        var children = try XCTUnwrap(root["children"] as? [[String: Any]])
        var member = try XCTUnwrap(children[0]["window"] as? [String: Any])
        member.removeValue(forKey: "freeSizeFrame")
        member.removeValue(forKey: "freeSizePreviousColumnWidth")
        member.removeValue(forKey: "freeSizePreviousFixedWidth")
        children[0]["window"] = member
        root["children"] = children
        object["root"] = root
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let record = try JSONDecoder().decode(FrozenStrip.self, from: legacy)

        restoreStrip(record, to: workspace, windowsById: [73022: window])
        XCTAssertNil(window.freeSizeRect)
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
