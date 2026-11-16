@testable import AppBundle
import XCTest

/// The recipes in docs/RECIPES.md parse cleanly, with nothing skipped as removed.
@MainActor
final class DocumentationExamplesTest: XCTestCase {
    private func assertParses(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let (config, errors) = parseConfig("config-version = 2\n" + text)
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"), file: file, line: line)
        XCTAssertEqual(config.ignoredConfiguration, [], file: file, line: line)
    }

    func testLoneWindowRecipeParses() {
        assertParses("""
            single-window-aspect-ratio = 1.4
            single-window-alignment = 'center'
            """)
    }

    func testSceneAccentRecipeParses() {
        assertParses("accent-color = '#205ea6'")
    }

    func testColumnWidthRecipeParses() {
        assertParses("""
            [scrolling]
            column-width = 0.3333
            width-presets = [0.3333, 0.5, 0.6667, 1.0]
            center-focused-column = 'on-overflow'
            """)
    }

    func testFloatingRuleRecipeParses() {
        assertParses("""
            [[on-window-detected]]
            if.app-id = 'com.apple.systempreferences'
            run = 'layout floating'
            """)
    }

    func testModifierSideRecipeParses() {
        assertParses("""
            [modifiers]
            alt = 'left'
            """)
    }

    func testLaunchOnlyRuleRecipeParses() {
        assertParses("""
            [[on-window-detected]]
            if.app-id = 'net.imput.helium'
            if.app-has-other-windows = false
            run = 'move-node-to-workspace 5'
            """)
    }
}
