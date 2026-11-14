@testable import AppBundle
import TOMLKit
import XCTest

@MainActor
final class SettingsPersistenceRegressionTest: XCTestCase {
    func testToggleUpdatesRootDottedKeysRepeatedly() throws {
        var text = "scrolling.minimap-enabled = true # keep this explanation\nscrolling.column-width = 0.4\n[menu-bar]\nindicator = 'icon'\n"
        for enabled in [false, true, false] {
            text = updateSettingsScalarConfig(in: text, section: "scrolling", key: "minimap-enabled", renderedValue: String(enabled))
            let parsed = parseConfig(text)
            XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
            XCTAssertEqual(parsed.config.scrolling.minimapEnabled, enabled)
            XCTAssertEqual(parsed.config.scrolling.columnWidth, 0.4)
            XCTAssertTrue(text.contains("# keep this explanation"))
            XCTAssertFalse(text.contains("[scrolling]"))
        }
    }

    func testTwoKeysOfOneTablePersistIndependently() {
        for dotted in [true, false] {
            var text = dotted
                ? "native-spaces.restore-layouts = true\nnative-spaces.restore-frames-on-quit = true\n"
                : "[native-spaces]\nrestore-layouts = true\nrestore-frames-on-quit = true\n"
            for (layouts, frames) in [(false, true), (true, false), (false, false), (true, true)] {
                text = applyingSettingsConfigEdits([
                    .init(section: "native-spaces", key: "restore-layouts", renderedValue: String(layouts)),
                    .init(section: "native-spaces", key: "restore-frames-on-quit", renderedValue: String(frames)),
                ], to: text)
                let parsed = parseConfig(text)
                XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
                XCTAssertEqual(parsed.config.nativeSpaces.restoreLayouts, layouts)
                XCTAssertEqual(parsed.config.nativeSpaces.restoreFramesOnQuit, frames)
            }
        }
    }

    func testMissingKeyUsesExistingDottedTableAndCommentedHeader() {
        for original in ["scrolling.column-width = 0.4\n", "[ scrolling ] # dimensions\ncolumn-width = 0.4\n", "[\"scrolling\"] # dimensions\ncolumn-width = 0.4\n"] {
            let updated = updateSettingsScalarConfig(in: original, section: "scrolling", key: "minimap-enabled", renderedValue: "false")
            let parsed = parseConfig(updated)
            XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
            XCTAssertFalse(parsed.config.scrolling.minimapEnabled)
            XCTAssertEqual(parsed.config.scrolling.columnWidth, 0.4)
        }
    }

    func testNestedGapTableAndMultilineOverridesRemainValid() {
        let original = """
        [gaps.outer] # use the existing nested table
        left = [
            { monitor."Disconnected [Panel]" = 24 }, # keep override
            8 # keep default explanation
        ]
        right = 12
        [scrolling]
        minimap-enabled = true
        """
        let rules = parseConfig(original).config.gaps.outer.left
        let updated = updateSettingsScalarConfig(in: original, section: "gaps", key: "outer.left",
            renderedValue: settingsGapValue(rules, replacingDefaultWith: 16))
        let parsed = parseConfig(updated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.gaps.outer.left, .perMonitor(rulesForDisconnectedPanel(), default: 16))
        XCTAssertEqual(parsed.config.gaps.outer.right, .constant(12))
        XCTAssertTrue(updated.contains("# keep override"))
        XCTAssertTrue(updated.contains("# keep default explanation"))
    }

    private func rulesForDisconnectedPanel() -> [PerMonitorValue<Int>] {
        parseConfig("[gaps]\nouter.left = [{ monitor.\"Disconnected [Panel]\" = 24 }, 0]").config.gaps.outer.left.rulesForTest
    }

    func testExplicitArrayRemovalPreservesComments() {
        let original = """
        config-version = 2
        persistent-workspaces = [
            "one", # named slot
            "two"
        ] # previous list
        scrolling.minimap-enabled = true
        """
        let updated = applyingSettingsConfigEdits([
            .init(section: "menu-bar", key: "indicator", renderedValue: "'workspace'"),
            .init(section: nil, key: "persistent-workspaces", renderedValue: nil),
        ], to: original)
        let parsed = parseConfig(updated)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.menuBar.indicator, .workspace)
        XCTAssertTrue(parsed.config.persistentWorkspaces.isEmpty)
        XCTAssertTrue(parsed.config.scrolling.minimapEnabled)
        XCTAssertTrue(updated.contains("# named slot"))
        XCTAssertTrue(updated.contains("# previous list"))
    }

    func testMultilineStringCannotMasqueradeAsASection() throws {
        let original = "message = '''\n[scrolling]\nminimap-enabled = false\n'''\nscrolling.minimap-enabled = true\n"
        let updated = updateSettingsScalarConfig(in: original, section: "scrolling", key: "minimap-enabled", renderedValue: "false")
        let table = try TOMLTable(string: updated)
        XCTAssertEqual(table["message"]?.string, "[scrolling]\nminimap-enabled = false\n")
        XCTAssertEqual(table["scrolling"]?.table?["minimap-enabled"]?.bool, false)
    }
}

private extension DynamicConfigValue where Value == Int {
    var rulesForTest: [PerMonitorValue<Int>] {
        if case .perMonitor(let rules, _) = self { return rules }
        return []
    }
}
