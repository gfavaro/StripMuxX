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

    func testAFloatingWindowCanBeAddedToTheStripFromTheMenuWhetherOrNotItHasFocus() throws {
        let workspace = focus.workspace
        let tiled = TestWindow.new(id: 97010, parent: workspace.rootTilingContainer)
        XCTAssertTrue(tiled.focusWindow())
        func titles() -> [String] { let menu = NSMenu(); NativeActionMenu().menuNeedsUpdate(menu); return menu.items.map(\.title) }
        XCTAssertFalse(titles().contains { $0.contains("to Strip") }, "Nothing to add: no entry")

        let floating = TestWindow.new(id: 97011, parent: workspace)
        floating.nativeLayoutEligible = true
        let single = titles().first { $0.hasSuffix("to Strip") }
        XCTAssertNotNil(single, "One floating window is a single item")
        let menu = NSMenu(); NativeActionMenu().menuNeedsUpdate(menu)
        let item = try XCTUnwrap(menu.items.first { $0.title == single })
        XCTAssertTrue(item.isEnabled, "It is enabled although the tiled window has focus")
        let payload = try XCTUnwrap(item.representedObject as? MenuCommandPayload)
        let layout = try XCTUnwrap(payload.commands.first as? LayoutCommand)
        XCTAssertEqual(layout.args.windowId, 97011, "It acts on that window, not the focused one")

        let second = TestWindow.new(id: 97012, parent: workspace)
        second.nativeLayoutEligible = true
        let several = NSMenu(); NativeActionMenu().menuNeedsUpdate(several)
        let submenu = try XCTUnwrap(several.items.first { $0.title == "Add Floating Window to Strip" }?.submenu)
        XCTAssertEqual(submenu.items.count, 2, "Several are a submenu with one entry each")
    }
}
