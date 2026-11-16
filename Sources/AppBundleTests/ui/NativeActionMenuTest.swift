@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class NativeActionMenuTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests(desktops: 2) }

    func testMenuOffersStripCommandsAndDesktops() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        config.modes[mainModeId] = parseConfig("""
        [mode.main.binding]
        alt-2 = 'workspace 2'
        """).config.modes[mainModeId]
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(titles.first, "StripMuxX · Space 1")
        for title in ["Center Column", "Show Minimap", "Cycle Column Width", "Pin Column Left", "Retile", "Balance Sizes",
                      "Fullscreen", "Commands", "Settings…", "Enabled", "Quit StripMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        for title in ["Dwindle", "Master", "No Peek", "Borders", "Focus Follows Pointer"] {
            XCTAssertFalse(titles.contains(title), title)
        }
        let commands = try XCTUnwrap(menu.items.first { $0.title == "Commands" }?.submenu)
        for title in ["Spaces", "Focus", "Move Window", "Stack With Column", "Resize", "Toggle Floating",
                      "Refresh Spaces", "Reload Config"] {
            XCTAssertTrue(commands.items.contains { $0.title == title }, title)
        }
        XCTAssertFalse(commands.items.contains { $0.title == "Container Layout" })
        let desktops = try XCTUnwrap(commands.items.first { $0.title == "Spaces" }?.submenu)
        XCTAssertEqual(desktops.items.first { $0.title == "Space 1" }?.state, .on)
        XCTAssertEqual(desktops.items.first { $0.title == "Space 2" }?.keyEquivalent, "2")
        XCTAssertTrue(runtime.native.accepts(try XCTUnwrap(parseCommand("retile").cmdOrNil)))
    }
}
