@testable import AppBundle
import Common
import XCTest

/// The strip's tree commands: a desktop is one row of columns, and a column is a
/// window or a vertical stack.
@MainActor
final class StripCommandsTest: WorkspaceTestCase {
    private func strip(_ count: Int) -> (Workspace, [TestWindow]) {
        let workspace = focus.workspace
        let windows = (0..<count).map { TestWindow.new(id: UInt32(8300 + $0), parent: workspace.rootTilingContainer) }
        return (workspace, windows)
    }

    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).unwrap().0).run(.defaultEnv, .emptyStdin)
    }

    private func columns(_ workspace: Workspace) -> [[UInt32]] {
        workspace.rootTilingContainer.children.map { $0.allLeafWindowsRecursive.map(\.windowId) }
    }

    func testMoveCarriesTheColumnAlongTheStrip() async throws {
        let (workspace, windows) = strip(3)
        _ = windows[0].focusWindow()
        let right = try await run("move right")
        XCTAssertEqual(right.exitCode, 0)
        XCTAssertEqual(columns(workspace), [[8301], [8300], [8302]])
        _ = try await run("move right")
        let atEnd = try await run("move right")
        XCTAssertEqual(atEnd.exitCode, 0, "The strip's end is not a failure by default")
        XCTAssertEqual(columns(workspace), [[8301], [8302], [8300]])
        let failing = try await run("move --boundaries-action fail right")
        XCTAssertNotEqual(failing.exitCode, 0)
    }

    func testJoinStacksAndMoveOutRestoresAColumn() async throws {
        let (workspace, windows) = strip(3)
        windows[1].scrollingColumnWidth = 0.6
        _ = windows[0].focusWindow()
        let joined = try await run("join-with right")
        XCTAssertEqual(joined.exitCode, 0)
        XCTAssertEqual(columns(workspace), [[8300, 8301], [8302]], "Joining to the right puts the window on top")
        let stack = try XCTUnwrap(workspace.rootTilingContainer.children.first as? TilingContainer)
        XCTAssertEqual(stack.orientation, .v)
        XCTAssertEqual(try XCTUnwrap(stack.scrollingColumnWidth), 0.6, accuracy: 0.001, "The stack takes the target column's width")

        let down = try await run("move down")
        XCTAssertEqual(down.exitCode, 0)
        XCTAssertEqual(columns(workspace), [[8301, 8300], [8302]])
        let out = try await run("move left")
        XCTAssertEqual(out.exitCode, 0)
        XCTAssertEqual(columns(workspace), [[8300], [8301], [8302]], "A stack of one becomes a plain column")
        XCTAssertTrue(workspace.rootTilingContainer.children.allSatisfy { $0 is Window })
        let sideways = try await run("join-with up").exitCode
        XCTAssertNotEqual(sideways, 0, "Columns join only sideways")
    }

    func testFocusCrossesColumnsAndWalksAStack() async throws {
        let (workspace, windows) = strip(3)
        stack(windows[2], with: windows[1], above: false, in: workspace)
        _ = windows[0].focusWindow()
        _ = try await run("focus right")
        XCTAssertEqual(focus.windowOrNil?.windowId, 8302, "A stack is entered at its most recent window")
        _ = try await run("focus up")
        XCTAssertEqual(focus.windowOrNil?.windowId, 8301)
        _ = try await run("focus left")
        XCTAssertEqual(focus.windowOrNil?.windowId, 8300)
    }

    func testFloatingLeavesTheStripAndTilingReturnsToIt() async throws {
        let (workspace, windows) = strip(3)
        stack(windows[1], with: windows[2], above: true, in: workspace)
        _ = windows[1].focusWindow()
        let floated = try await run("layout floating")
        XCTAssertEqual(floated.exitCode, 0)
        XCTAssertTrue(windows[1].parent === workspace)
        XCTAssertEqual(columns(workspace), [[8300], [8302]], "The stack left behind collapses")
        let floatingMove = try await run("move left").exitCode
        XCTAssertNotEqual(floatingMove, 0, "Floating windows have no place on the strip")
        let tiled = try await run("layout tiling")
        XCTAssertEqual(tiled.exitCode, 0)
        XCTAssertTrue(windows[1].parent === workspace.rootTilingContainer)
        XCTAssertEqual(Set(columns(workspace).flatMap { $0 }), [8300, 8301, 8302])
    }

    func testNextDetectedWindowLayoutAppliesOnce() async throws {
        let workspace = focus.workspace
        let armed = try await run("layout floating --for-next-detected-window")
        XCTAssertEqual(armed.exitCode, 0, armed.stderr.joined())
        let first = TestWindow.new(id: 8310, parent: workspace.rootTilingContainer)
        applyLayoutForNextDetectedWindow(first, on: workspace)
        XCTAssertTrue(first.parent === workspace)
        let second = TestWindow.new(id: 8311, parent: workspace.rootTilingContainer)
        applyLayoutForNextDetectedWindow(second, on: workspace)
        XCTAssertTrue(second.parent === workspace.rootTilingContainer)
    }

    func testFlattenTurnsEveryStackIntoColumns() async throws {
        let (workspace, windows) = strip(4)
        stack(windows[1], with: windows[0], above: false, in: workspace)
        stack(windows[3], with: windows[2], above: false, in: workspace)
        XCTAssertEqual(columns(workspace), [[8300, 8301], [8302, 8303]])
        _ = windows[0].focusWindow()
        let flattened = try await run("flatten-workspace-tree").exitCode
        XCTAssertEqual(flattened, 0)
        XCTAssertEqual(columns(workspace), [[8300], [8301], [8302], [8303]])
    }

    func testNormalizeKeepsTheStripShape() {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let lone = TilingContainer.newStack(in: workspace)
        _ = TestWindow.new(id: 8320, parent: lone)
        let outer = TilingContainer.newStack(in: workspace)
        _ = TestWindow.new(id: 8321, parent: outer)
        let nested = TilingContainer(parent: outer, adaptiveWeight: 1, .v, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 8322, parent: nested)
        _ = TestWindow.new(id: 8323, parent: nested)
        _ = TilingContainer.newStack(in: workspace)
        workspace.normalizeContainers()
        XCTAssertEqual(columns(workspace), [[8320], [8321, 8322, 8323]])
        XCTAssertTrue(root.children[0] is Window, "A stack of one is a plain column")
        let stack = try? XCTUnwrap(root.children[1] as? TilingContainer)
        XCTAssertTrue(stack?.children.allSatisfy { $0 is Window } == true, "Stacks never nest")
    }
}
