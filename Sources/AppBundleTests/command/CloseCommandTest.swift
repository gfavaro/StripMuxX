@testable import AppBundle
import Common
import XCTest

@MainActor
final class CloseCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSimple() async throws {
        focus.workspace.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 2)

        try await CloseCommand(args: CloseCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, 2)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 1)
    }

    func testClosingFocusedWindowReturnsToPreviouslyFocusedColumn() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 91001, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 91002, parent: workspace.rootTilingContainer)
        let third = TestWindow.new(id: 91003, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        _ = second.focusWindow()
        _ = third.focusWindow()
        XCTAssertTrue(workspace.previousFocusedWindow === second)
        try await CloseCommand(args: CloseCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focus.windowOrNil?.windowId, second.windowId)
    }

    func testClosingUnfocusedWindowDoesNotStealFocus() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 91011, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 91012, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        try await CloseCommand(args: CloseCmdArgs(rawArgs: []).copy(\.windowId, 91012)).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(focus.windowOrNil?.windowId, first.windowId)
    }

    func testCloseViaWindowIdFlag() async throws {
        focus.workspace.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 2)

        try await CloseCommand(args: CloseCmdArgs(rawArgs: []).copy(\.windowId, 2)).run(.defaultEnv, .emptyStdin)

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.rootTilingContainer.children.count, 1)
    }
}
