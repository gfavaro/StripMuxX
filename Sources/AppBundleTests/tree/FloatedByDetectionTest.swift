@testable import AppBundle
import Common
import XCTest

/// A window that floated only because it looked like a dialog when first seen must be able to return to the
/// strip; one a person floated must stay put.
@MainActor
final class FloatedByDetectionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func run(_ text: String) async throws -> CmdResult {
        try await XCTUnwrap(parseCommand(text).unwrap().0).run(.defaultEnv, .emptyStdin)
    }

    func testOnlyADetectionFloatedWindowThatNowLooksOrdinaryReturnsToTheStrip() {
        for type in [AxUiElementWindowType.window, .dialog, .popup] {
            XCTAssertTrue(floatedWindowStaysFloating(floatedByDetection: false, type: type), "A window someone floated stays: \(type)")
        }
        XCTAssertFalse(floatedWindowStaysFloating(floatedByDetection: true, type: .window), "It looks like a window now")
        XCTAssertTrue(floatedWindowStaysFloating(floatedByDetection: true, type: .dialog), "A real dialog stays floating")
        XCTAssertTrue(floatedWindowStaysFloating(floatedByDetection: true, type: .popup))
    }

    func testTheFlagIsSavedWithTheLayoutAndOlderFilesWithoutItStillLoad() throws {
        let window = TestWindow.new(id: 99020, parent: focus.workspace.rootTilingContainer)
        XCTAssertNil(FrozenWindow(window).floatedByDetection, "Nothing is stored for an ordinary window")
        window.floatedByDetection = true
        let encoded = try JSONEncoder().encode(FrozenWindow(window))
        let restored = try JSONDecoder().decode(FrozenWindow.self, from: encoded)
        XCTAssertEqual(restored.floatedByDetection, true)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "floatedByDetection")
        let old = try JSONDecoder().decode(FrozenWindow.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.floatedByDetection, "A layout saved before the flag existed loads with it unset")
    }

    func testChoosingALayoutClearsTheFlag() async throws {
        let window = TestWindow.new(id: 99030, parent: focus.workspace.rootTilingContainer)
        XCTAssertTrue(window.focusWindow())
        window.floatedByDetection = true
        _ = try await run("layout floating")
        XCTAssertTrue(window.parent is Workspace, "It floats")
        XCTAssertFalse(window.floatedByDetection, "and now because it was asked to")
    }
}
