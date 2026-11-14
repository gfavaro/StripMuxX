@testable import AppBundle
import XCTest

final class SetupCheckTest: XCTestCase {
    private let healthy = SetupCheckInput(accessibilityGranted: true, otherWindowManagers: [],
                                          separateSpaces: true, rearrangesSpaces: false)

    private func failing(_ input: SetupCheckInput) -> [String] { setupCheckItems(input).filter { !$0.ok }.map(\.id) }

    func testHealthySetupPasses() {
        XCTAssertEqual(failing(healthy), [])
    }

    func testEachProblemIsReportedWithAFix() {
        var input = healthy
        input.accessibilityGranted = false
        input.otherWindowManagers = ["yabai"]
        XCTAssertEqual(failing(input), ["accessibility", "other-window-managers"])
        XCTAssertTrue(setupCheckItems(input).first { $0.id == "other-window-managers" }!.detail.contains("yabai"))
        XCTAssertNotNil(setupCheckItems(input).first { $0.id == "accessibility" }?.fixURL)
    }

    func testSpacesSettingsAreChecked() {
        var input = healthy
        input.separateSpaces = false
        input.rearrangesSpaces = true
        XCTAssertEqual(failing(input), ["separate-spaces", "rearrange-spaces"])
        XCTAssertNotNil(setupCheckItems(input).first { $0.id == "separate-spaces" }?.fixURL)
    }
}
