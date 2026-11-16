@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowWidthTest: WorkspaceTestCase {
    private func load(_ text: String) throws {
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        config.singleWindowAspectRatio = parsed.config.singleWindowAspectRatio
        config.singleWindowAlignment = parsed.config.singleWindowAlignment
        config.displayWindowSettings = parsed.config.displayWindowSettings
    }

    private func limitedWidth(_ workspace: Workspace, ratio: Double) -> CGFloat {
        let available = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        return min(available.width, max(available.height - 1, 0) * CGFloat(ratio))
    }

    func testLoneWindowKeepsItsShapeAndFullscreenFillsTheDisplay() async throws {
        try load("single-window-aspect-ratio = 0.8")
        let workspace = focus.workspace
        let lone = TestWindow.new(id: 72010, parent: workspace.rootTilingContainer)
        let available = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        XCTAssertEqual(workspaceTilingRect(workspace).width, limitedWidth(workspace, ratio: 0.8), accuracy: 0.001)
        XCTAssertEqual(workspaceTilingRect(workspace).height, available.height, accuracy: 0.001)
        lone.isFullscreen = true
        XCTAssertEqual(fullscreenWindowRect(lone, in: workspace).width, available.width, accuracy: 0.001,
                       "Managed fullscreen is not limited by the ratio")
        lone.isFullscreen = false

        try load("single-window-aspect-ratio = 0")
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width, accuracy: 0.001, "0 fills the width")
    }

    func testDefaultRatioAppliesWithoutAnyConfiguration() async throws {
        try load("")
        let workspace = focus.workspace
        _ = TestWindow.new(id: 72030, parent: workspace.rootTilingContainer)
        XCTAssertEqual(config.singleWindowAspectRatio, defaultSingleWindowAspectRatio)
        XCTAssertEqual(workspaceTilingRect(workspace).width,
                       limitedWidth(workspace, ratio: defaultSingleWindowAspectRatio), accuracy: 0.001)
    }

    func testDisplayOverridesTheRatioAndKeepsTheGlobalAlignment() async throws {
        try load("""
            single-window-aspect-ratio = 2.0
            single-window-alignment = 'left'
            [display.main]
            single-window-aspect-ratio = 0.8
            """)
        let workspace = focus.workspace
        _ = TestWindow.new(id: 72020, parent: workspace.rootTilingContainer)
        let available = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        let rect = workspaceTilingRect(workspace)
        XCTAssertEqual(rect.width, limitedWidth(workspace, ratio: 0.8), accuracy: 0.001,
                       "The display's ratio wins over the global one")
        XCTAssertEqual(rect.topLeftX, available.topLeftX, accuracy: 0.001, "and inherits the global alignment")
        _ = TestWindow.new(id: 72021, parent: workspace.rootTilingContainer)
        XCTAssertEqual(workspaceTilingRect(workspace).width, available.width, accuracy: 0.001,
                       "A second column ends the lone-window limit")
    }

    func testRangeAndTypesAtEveryScope() {
        for prefix in ["", "[display.main]\n"] {
            for value in ["-0.1", "6.1", "nan", "inf", "-inf", "'1.5'", "true", "[]"] {
                XCTAssertFalse(parseConfig(prefix + "single-window-aspect-ratio = " + value).errors.isEmpty, prefix + value)
            }
            for value in ["0", "0.5", "1.6", "6"] {
                XCTAssertTrue(parseConfig(prefix + "single-window-aspect-ratio = " + value).errors.isEmpty, prefix + value)
            }
            XCTAssertFalse(parseConfig(prefix + "single-window-alignment = 'top'").errors.isEmpty)
        }
        XCTAssertFalse(parseConfig("[display.main]\nsingle-window-aspect-rato = 1.6").errors.isEmpty)
        XCTAssertFalse(parseConfig("display = []").errors.isEmpty)
        XCTAssertFalse(parseConfig("[display.'']\nsingle-window-aspect-ratio = 1.6").errors.isEmpty)
    }

    func testRemovedPercentageKeysAreIgnoredNotErrors() {
        let parsed = parseConfig("fullscreen-width = 0.6\nlone-window-width = 0.7\n[scrolling]\ngesture-smoothing = 40\ngesture-sensitivity = 1.0")
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.ignoredConfiguration,
                       ["fullscreen-width", "lone-window-width", "scrolling.gesture-sensitivity", "scrolling.gesture-smoothing"])
    }

    func testFullscreenFillsTheDisplayAndHonorsNoOuterGaps() async throws {
        try load("single-window-aspect-ratio = 0.8\nsingle-window-alignment = 'right'")
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 72001, parent: root)
        let window = TestWindow.new(id: 72002, parent: root)
        window.markAsMostRecentChild()
        window.isFullscreen = true
        for noGaps in [false, true] {
            window.noOuterGapsInFullscreen = noGaps
            let monitor = workspace.workspaceMonitor
            let available = noGaps ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
            try await workspace.layoutWorkspace()
            let actual = try await window.getAxRect()
            let frame = try XCTUnwrap(actual)
            XCTAssertEqual(frame.width, available.width, accuracy: 0.001)
            XCTAssertEqual(frame.topLeftX, available.topLeftX, accuracy: 0.001)
        }
        window.isFullscreen = false
    }
}
