@testable import AppBundle
import SwiftUI
import XCTest

@MainActor
final class SettingsSearchTest: XCTestCase {
    func testSearchFindsRelevantStripSettingsWithoutVirtualWorkspaceControls() {
        XCTAssertEqual(settingsControlSearchResults("three finger"), [.threeFingers])
        XCTAssertEqual(settingsControlSearchResults("minimap"), [.minimap, .minimapHold])
        XCTAssertTrue(settingsControlSearchResults("sidebar").isEmpty)
        XCTAssertEqual(settingsControlSearchResults("column size shortcuts"), [.widthPresets])
        XCTAssertEqual(settingsControlSearchResults("single-window width"), [.loneWidth], "The setting's earlier name still finds it")
        XCTAssertEqual(settingsControlSearchResults("fullscreen width"), [.fullscreenWidth])
        XCTAssertEqual(settingsControlSearchResults("single window alignment"), [.loneAlignment])
        XCTAssertEqual(settingsControlSearchResults("left screen spacing"), [.gapOuterLeft])
    }

    func testEveryBorderSettingIsSearchableAndOpensItsControl() {
        XCTAssertEqual(Set(settingsControlSearchResults("border")), Set([
            .bordersEnabled, .borderWidth, .borderActiveColor, .borderInactiveColor, .borderOrder,
            .borderExcludeApps, .borderHideWhileScrolling,
        ]))
        XCTAssertEqual(settingsControlSearchResults("hide borders while scrolling"), [.borderHideWhileScrolling])
        XCTAssertEqual(settingsControlSearchResults("colour"), [.borderActiveColor, .borderInactiveColor], "Either spelling")
        XCTAssertEqual(settingsControlSearchResults("trail"), [.borderHideWhileScrolling])
        XCTAssertTrue(SettingsControl.allCases.filter { $0.id.hasPrefix("borders.") }.allSatisfy { $0.page == .appearance })
    }

    func testSubmitPrefersControlOverPageAndFallsBackToPage() {
        XCTAssertEqual(settingsSearchSubmitSelection(controls: [.gestures], pages: [.windows]),
                       .control(.gestures))
        XCTAssertEqual(settingsSearchSubmitSelection(controls: [], pages: [.general]),
                       .page(.general))
        XCTAssertNil(settingsSearchSubmitSelection(controls: [], pages: []))
    }

    func testPageSearchIncludesReferenceDescriptions() {
        XCTAssertTrue(settingsPageSearchResults("minimap", pages: [.general, .windows]).contains(.windows))
        XCTAssertEqual(settingsPageSearchResults("", pages: [.general, .windows]), [.general, .windows])
    }
}
