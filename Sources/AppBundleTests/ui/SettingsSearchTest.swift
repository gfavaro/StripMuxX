@testable import AppBundle
import SwiftUI
import XCTest

@MainActor
final class SettingsSearchTest: XCTestCase {
    func testSearchFindsRelevantStripSettingsWithoutVirtualWorkspaceControls() {
        XCTAssertEqual(settingsControlSearchResults("three finger"), [.threeFingers])
        XCTAssertEqual(settingsControlSearchResults("minimap"), [.minimap, .minimapHold])
        XCTAssertTrue(settingsControlSearchResults("sidebar").isEmpty)
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
