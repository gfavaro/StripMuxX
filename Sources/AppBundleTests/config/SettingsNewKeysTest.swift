@testable import AppBundle
import Common
import XCTest

/// Every key the Settings window writes must land as TOML the parser reads back.
@MainActor
final class SettingsNewKeysTest: XCTestCase {
    private func write(_ text: String, _ edits: [(String?, String, String)]) -> Config {
        let result = applyingSettingsConfigEdits(edits.map { SettingsConfigEdit(section: $0.0, key: $0.1, renderedValue: $0.2) }, to: text)
        let parsed = parseConfig(result)
        XCTAssertEqual(parsed.errors.descriptions, [], result)
        return parsed.config
    }

    func testSettingsWritesForEveryNewKeyParseBack() {
        let config = write("", [
            ("scrolling", "center-focused-column", "'on-overflow'"),
            ("scrolling", "edge-preview", "12"),
            ("scrolling", "minimap-hold-modifiers", tomlCommaSeparatedStringArray("ctrl, alt")),
            ("scrolling", "keep-window-height", "true"),
            ("scrolling", "three-finger-swipe", "true"),
            ("native-spaces", "restore-layouts", "false"),
            ("native-spaces", "restore-frames-on-quit", "false"),
        ])
        XCTAssertEqual(config.scrolling.centerFocusedColumn, .onOverflow)
        XCTAssertEqual(config.scrolling.edgePreview, 12)
        XCTAssertEqual(config.scrolling.minimapHoldModifiers, [.control, .option])
        XCTAssertTrue(config.scrolling.keepWindowHeight)
        XCTAssertTrue(config.scrolling.threeFingerSwipe)
        XCTAssertFalse(config.nativeSpaces.restoreLayouts)
        XCTAssertFalse(config.nativeSpaces.restoreFramesOnQuit)
    }

    func testMinimapHoldKeysRoundTripAndRejectUnknownNames() {
        XCTAssertEqual(minimapHoldModifierNames([.option, .control]), "ctrl, alt")
        XCTAssertNil(minimapHoldModifierError("ctrl, alt"))
        XCTAssertNil(minimapHoldModifierError(""))
        XCTAssertNotNil(minimapHoldModifierError("ctrl, hyper"))
    }
}
