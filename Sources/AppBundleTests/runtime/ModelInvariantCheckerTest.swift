@testable import AppBundle
import XCTest

@MainActor
final class ModelInvariantCheckerTest: WorkspaceTestCase {
    func testColumnsStacksFloatingAndEmptyDesktopsAreValid() {
        let workspace = focus.workspace
        let stack = TilingContainer.newStack(in: workspace)
        let windows = [TestWindow.new(id: 1, parent: workspace),
                       TestWindow.new(id: 2, parent: workspace.rootTilingContainer),
                       TestWindow.new(id: 3, parent: stack),
                       TestWindow.new(id: 4, parent: stack)]
        _ = Workspace.get(byName: "empty")
        XCTAssertEqual(runtime.modelInvariantViolations(expectedWindows: windows), [])
    }

    func testBrokenIndexesAndViewportHaveSpecificViolations() {
        let workspace = Workspace.get(byName: "one")
        runtime.workspaces.workspaceIdByName.removeValue(forKey: workspace.name)
        XCTAssertTrue(runtime.modelInvariantViolations().contains { $0.kind == .nameIndex })
        runtime.workspaces.workspaceIdByName[workspace.name] = workspace.id
        let first = MonitorViewportId(topLeftCorner: .zero)
        let second = MonitorViewportId(topLeftCorner: .init(x: -100, y: 0))
        runtime.workspaces.monitorViewportsById[first] = MonitorViewport(id: first, activeWorkspaceId: workspace.id)
        runtime.workspaces.monitorViewportsById[second] = MonitorViewport(id: second, activeWorkspaceId: workspace.id)
        XCTAssertTrue(runtime.modelInvariantViolations().contains { $0.kind == .duplicateActiveWorkspace })
        runtime.workspaces.workspaceById.removeValue(forKey: workspace.id)
        XCTAssertTrue(runtime.modelInvariantViolations().contains { $0.kind == .viewport })
    }

    func testRegistryIdentityCorruptionIsDetected() {
        let workspace = Workspace.get(byName: "one")
        let wrongID = WorkspaceId("wrong-key")
        runtime.workspaces.workspaceById[wrongID] = workspace
        let kinds = Set(runtime.modelInvariantViolations().map(\.kind))
        XCTAssertTrue(kinds.contains(.registry))
        XCTAssertTrue(kinds.contains(.duplicateNode))
    }

    func testDuplicateWindowIDAndDetachedExpectedObjectAreDetected() {
        let workspace = Workspace.get(byName: "one")
        let first = TestWindow.new(id: 7, parent: workspace)
        let second = TestWindow.new(id: 7, parent: focus.workspace.rootTilingContainer)
        XCTAssertTrue(runtime.modelInvariantViolations().contains { $0.kind == .duplicateWindowID })
        second.unbindFromParent()
        XCTAssertEqual(runtime.modelInvariantViolations(expectedWindows: [first, second]).map(\.kind), [.missingWindow])
        XCTAssertEqual(runtime.modelInvariantViolations(), []) // closed/detached windows are allowed
    }
}
