@testable import AppBundle
import XCTest

final class SettingsColumnPresetChoicesTest: XCTestCase {
    func testToggleKeepsAscendingDistinctPresets() {
        let regular = [0.3333, 0.5, 0.6667, 1.0]
        XCTAssertEqual(SettingsColumnPresetChoices.toggled(0.25, in: regular),
                       [0.25, 0.3333, 0.5, 0.6667, 1.0])
        XCTAssertEqual(SettingsColumnPresetChoices.toggled(0.5, in: regular),
                       [0.3333, 0.6667, 1.0])
    }
    func testCustomPresetsSurviveCheckboxChanges() {
        let current = [0.27, 0.3333, 0.5, 0.85]
        XCTAssertEqual(SettingsColumnPresetChoices.toggled(0.5, in: current),
                       [0.27, 0.3333, 0.85])
    }
    func testNeverRemoveLastPreset() {
        XCTAssertEqual(SettingsColumnPresetChoices.toggled(0.5, in: [0.5]), [0.5])
    }
}
