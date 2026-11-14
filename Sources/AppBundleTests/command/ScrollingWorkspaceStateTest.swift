@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class ScrollingWorkspaceStateTest: WorkspaceTestCase {
    private func run(_ text: String) async throws {
        let result = try await XCTUnwrap(parseCommand(text).cmdOrNil).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
    }

    func testMinimumSwallowedResizeKeepsPreferredWidthAndNormalResizeUsesContentWidth() async throws {
        let workspace = focus.workspace
        let a = TestWindow.new(id: 98101, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 98102, parent: workspace.rootTilingContainer)
        a.scrollingColumnWidth = 0.3
        a.testMinimumSize = CGSize(width: 1200, height: 0)
        _ = a.focusWindow()
        let width = try XCTUnwrap(workspace.scrollingMetrics.columns.first).width
        try await run("resize width -10")
        try await run("resize smart -10")
        XCTAssertEqual(a.scrollingColumnWidth, 0.3)
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingMetrics.columns.first).width, width)
        a.testMinimumSize = .zero
        a.scrollingColumnWidth = 0.3
        let before = try XCTUnwrap(workspace.scrollingMetrics.columns.first).width
        try await run("resize width +80")
        XCTAssertEqual(try XCTUnwrap(workspace.scrollingMetrics.columns.first).width, before + 80, accuracy: 1)
    }

    func testConfigurationRejectsInvalidWidthsAndAcceptsAnyFinitePositiveSensitivity() {
        for value in ["nan", "inf", "0", "-1"] {
            XCTAssertFalse(parseConfig("[scrolling]\ngesture-sensitivity = \(value)").errors.isEmpty)
        }
        XCTAssertTrue(parseConfig("[scrolling]\ngesture-sensitivity = 12.5").errors.isEmpty)
        for presets in ["[]", "[0.5, 0.25]", "[0.5, 0.5]", "[0.09, 0.5]"] {
            XCTAssertFalse(parseConfig("[scrolling]\nwidth-presets = \(presets)").errors.isEmpty)
        }
    }
}
