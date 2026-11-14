@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class MenuBarLayoutIconTest: XCTestCase {
    func testMonochromeIconIsATemplateAndColorOrTintIsNot() {
        XCTAssertTrue(MenuBarLayoutIcon.image(monochrome: true).isTemplate)
        XCTAssertFalse(MenuBarLayoutIcon.image(monochrome: false).isTemplate)
        XCTAssertFalse(MenuBarLayoutIcon.image(monochrome: true, tint: .systemRed).isTemplate)
        XCTAssertEqual(MenuBarLayoutIcon.image(monochrome: true).size, MenuBarLayoutIcon.size)
    }

    func testDisabledShowsThePauseSymbol() {
        let disabled = menuBarIconImage(enabled: false, appearance: .color)
        XCTAssertEqual(disabled?.accessibilityDescription, "StripMuxX disabled")
        XCTAssertNotNil(menuBarIconImage(enabled: true, appearance: .monochrome))
    }
}
