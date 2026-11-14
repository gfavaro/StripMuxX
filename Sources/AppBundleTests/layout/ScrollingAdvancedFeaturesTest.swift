@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingAdvancedFeaturesTest: WorkspaceTestCase {
    private func run(_ text: String) async throws {
        let result = try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
    }

    func testPanDoesNotChangeFocus() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 73401, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 73402, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 73403, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        let start = workspace.scrollingOffset
        try await run("scrolling-pan right")
        XCTAssertGreaterThan(workspace.scrollingOffset, start)
        XCTAssertTrue(focus.windowOrNil === first)
        try await run("scrolling-pan left")
        XCTAssertEqual(workspace.scrollingOffset, start, accuracy: 1)
    }

    func testAbsoluteWidthSurvivesSnapshotAndRelativePresetResetsIt() async throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 73411, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 73412, parent: workspace.rootTilingContainer)
        _ = first.focusWindow()
        try await run("scrolling-width-pixels 420")
        XCTAssertEqual(first.scrollingColumnFixedWidth, 420)
        let snap = try JSONDecoder().decode(FrozenStrip.self, from: JSONEncoder().encode(FrozenStrip(workspace)))
        if case .window(let window) = snap.root.children[0] {
            XCTAssertEqual(window.scrollingColumnFixedWidth, 420)
        } else { XCTFail("Expected a window column") }
        let cols: [ScrollingWorkspaceGeometryInput.Column] = [
            .init(preferredWidth: 0.5, minimumWidth: 0, fixedWidth: 420),
            .init(preferredWidth: 0.5, minimumWidth: 0),
        ]
        for screen in [1000.0, 1400.0] {
            let r = CGRect(x: 0, y: 0, width: screen, height: 700)
            let geometry = calculateScrollingWorkspaceGeometry(.init(bounds: r, parkingBounds: r,
                offset: 0, columns: cols, horizontalGap: 0, outerLeft: 0, outerRight: 0,
                leftWall: false, rightWall: false, preview: 25))
            XCTAssertEqual(geometry.columns[0].spanWidth, 420)
        }
        try await run("scrolling-width next")
        XCTAssertNil(first.scrollingColumnFixedWidth)
    }

    func testNiriOnOverflowRelativeToPreviousColumn() {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 73421, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 73422, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 73423, parent: workspace.rootTilingContainer)
        for w in workspace.rootTilingContainer.allLeafWindowsRecursive { w.scrollingColumnWidth = 0.45 }
        _ = a.focusWindow()
        let metrics = workspace.scrollingMetrics
        let current = metrics.clampedOffset(0)
        XCTAssertEqual(metrics.focusedOffset(for: metrics.columns[1], current: current, mode: .onOverflow,
            previous: metrics.columns[0]), metrics.revealedOffset(for: metrics.columns[1], current: current))
        XCTAssertEqual(metrics.focusedOffset(for: metrics.columns[2], current: current, mode: .onOverflow,
            previous: metrics.columns[0]), metrics.centeredOffset(for: metrics.columns[2]))
    }


    func testFixedWidthHonorsMinimumAndSurvivesStackNormalization() throws {
        let workspace = focus.workspace
        let first = TestWindow.new(id: 73431, parent: workspace.rootTilingContainer)
        let second = TestWindow.new(id: 73432, parent: workspace.rootTilingContainer)
        let minimum = calculateScrollingWorkspaceGeometry(.init(
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            parkingBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            offset: 0, columns: [
                .init(preferredWidth: 0.5, minimumWidth: 620, fixedWidth: 420),
                .init(preferredWidth: 0.5, minimumWidth: 0)
            ], horizontalGap: 0, outerLeft: 0, outerRight: 0,
            leftWall: false, rightWall: false, preview: 25
        ))
        XCTAssertEqual(minimum.columns[0].spanWidth, 620)

        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .v, index: 0)
        group.scrollingColumnFixedWidth = 420
        first.bind(to: group, adaptiveWeight: 1, index: 0)
        second.bind(to: group, adaptiveWeight: 1, index: 1)
        let frozen = FrozenStrip(workspace)
        let decoded = try JSONDecoder().decode(FrozenStrip.self, from: JSONEncoder().encode(frozen))
        if case .container(let stack) = decoded.root.children[0] {
            XCTAssertEqual(stack.scrollingColumnFixedWidth, 420)
        } else { XCTFail("Expected stacked column") }
    }

    func testInvalidCommands() {
        for command in ["scrolling-pan up", "scrolling-width-pixels 0", "scrolling-width-pixels abc"] {
            XCTAssertNil(parseCommand(command).cmdOrNil)
        }
    }
}
