@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowWidthTest: WorkspaceTestCase {
    private func load(_ text: String) throws {
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        config.fullscreenWidth = parsed.config.fullscreenWidth
        config.singleWindowAlignment = parsed.config.singleWindowAlignment
        config.displayWindowSettings = parsed.config.displayWindowSettings
    }

    func testRangeAndTypesAtEveryScope() {
        for prefix in ["", "[display.main]\n"] {
            for value in ["0", "0.09", "1.01", "nan", "inf", "-inf", "'0.7'", "true", "[]"] {
                XCTAssertFalse(parseConfig(prefix + "fullscreen-width = " + value).errors.isEmpty, prefix + value)
            }
            for value in ["0.1", "0.7", "1"] {
                XCTAssertTrue(parseConfig(prefix + "fullscreen-width = " + value).errors.isEmpty, prefix + value)
            }
            XCTAssertFalse(parseConfig(prefix + "single-window-alignment = 'top'").errors.isEmpty)
        }
        XCTAssertFalse(parseConfig("[display.main]\nfullscren-width = 0.7").errors.isEmpty)
        XCTAssertFalse(parseConfig("display = []").errors.isEmpty)
        XCTAssertFalse(parseConfig("[display.'']\nfullscreen-width = 0.7").errors.isEmpty)
    }

    func testFullscreenStaysCenteredAndHonorsNoOuterGaps() async throws {
        try load("fullscreen-width = 0.7\nsingle-window-alignment = 'right'")
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
            XCTAssertEqual(frame.width, available.width * 0.7, accuracy: 0.001)
            XCTAssertEqual(frame.topLeftX, available.topLeftX + available.width * 0.15, accuracy: 0.001)
            XCTAssertEqual(workspaceTilingRect(workspace), frame)
        }
        window.isFullscreen = false
        XCTAssertEqual(workspaceTilingRect(workspace), workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)
    }

}
