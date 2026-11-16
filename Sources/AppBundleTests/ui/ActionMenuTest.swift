@testable import AppBundle
import AppKit
import Common
import HotKey
import XCTest

@MainActor
final class ActionMenuTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func command(_ script: String) throws -> any Command {
        guard case .cmd(let command) = parseCommand(script) else {
            XCTFail("Invalid command: \(script)")
            throw NSError(domain: "ActionMenuTest", code: 1)
        }
        return command
    }

    private func mode(_ text: String, name: String = "main") throws -> Mode {
        let (parsed, errors) = parseConfig("shortcuts-preset = 'none'\n" + text)
        XCTAssertTrue(errors.isEmpty, errors.descriptions.joined(separator: "\n"))
        return try XCTUnwrap(parsed.modes[name])
    }

    func testAllCatalogActionsParseAndHaveUniqueCommandsAndIds() throws {
        let actions = buildShortcutSections().flatMap(\.actions)
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count)
        XCTAssertEqual(Set(actions.map(\.canonicalCommand)).count, actions.count)
        for action in actions { _ = try command(action.commandScript) }
    }

    func testSingleBindingUsesNativeShortcut() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-left = 'focus left'"))
        let matches = bindings.bindings(for: try command("focus left"))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].keyEquivalent, String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        XCTAssertEqual(matches[0].modifiers, .option)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testOnlyExactConfiguredLayoutGetsShortcut() throws {
        var bindings = ActionMenuBindings(mode: try mode("""
        [mode.main.binding]
        alt-r = 'scrolling-width next'
        alt-shift-t = 'layout floating tiling'
        """))
        XCTAssertEqual(bindings.bindings(for: try command("scrolling-width next")).map(\.notation), ["alt-r"])
        XCTAssertEqual(bindings.bindings(for: try command("layout floating tiling")).map(\.notation), ["alt-shift-t"])
        for script in ["scrolling-width full", "scrolling-width previous", "layout floating", "layout tiling floating"] {
            XCTAssertTrue(bindings.bindings(for: try command(script)).isEmpty, script)
        }
    }

    func testMenuHeaderNamesWorkspaceOnce() throws {
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let header = try XCTUnwrap(menu.items.first).title
        XCTAssertEqual(header, "StripMuxX · Space 1")
    }

    func testAboutItemSitsAboveSettingsAndCreditsTheFork() throws {
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        let about = try XCTUnwrap(titles.firstIndex(of: "About StripMuxX"))
        XCTAssertEqual(titles[about + 1], "Settings…")
        XCTAssertTrue(menu.items[about].isEnabled)
        let credits = aboutPanelCredits()
        XCTAssertTrue(credits.string.contains("WinMux by Zimeng Xiong"), credits.string)
        let link = credits.attribute(.link, at: credits.length - 1, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "https://github.com/gfavaro/StripMuxX")
    }

    func testEssentialMenuOmitsRareCommandsRatherThanNestingThem() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        for title in ["Center Column", "Show Minimap", "Retile", "Balance Sizes", "Fullscreen",
                      "Commands", "About StripMuxX", "Settings…", "Enabled", "Quit StripMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        for title in ["Spaces", "Focus", "Move Window", "Stack With Column", "Resize", "Reload Config", "Clear Saved Minimum Sizes…"] {
            XCTAssertFalse(titles.contains(title), "\(title) is not at the top level")
        }
        XCTAssertEqual(menu.items.filter { $0.submenu != nil }.map(\.title), ["Commands"])
        let commands = try submenu("Commands", in: menu)
        for title in ["Spaces", "Focus", "Move Window", "Stack With Column", "Resize", "Toggle Floating", "Reload Config"] {
            XCTAssertTrue(commands.items.contains { $0.title == title }, title)
        }
        XCTAssertFalse(titles.contains("Mode: main"))
        func descendants(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(descendants) ?? []) }
        }
        let allTitles = descendants(menu).map(\.title)
        for title in ["Advanced", "Projects", "Utilities", "Other Key Bindings", "Bring Here", "Copy Version", "Open Config", "Diagnostics…", "Close Other Windows…", "New Opposite Container", "Next Tab"] {
            XCTAssertFalse(allTitles.contains(title), title)
        }
        let workspaces = try submenu("Spaces", in: commands)
        XCTAssertNotNil(workspaces.items.first { $0.title == "Move and Follow" }?.submenu)
        XCTAssertNotNil(workspaces.items.first { $0.title == "Move Window to" }?.submenu)
        if sortedMonitors.count == 1 { XCTAssertFalse(commands.items.contains { $0.title == "Display" }) }
    }

    private func submenu(_ title: String, in menu: NSMenu) throws -> NSMenu {
        try XCTUnwrap(menu.items.first { $0.title == title }?.submenu, title)
    }

    func testMultipleBindingsAreAllClaimed() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-left = 'focus left'\nalt-h = 'focus left'"))
        XCTAssertEqual(bindings.bindings(for: try command("focus left")).count, 2)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testMultiCommandBindingNeverLabelsOneAction() throws {
        var bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-h = ['focus left', 'mode main']"))
        XCTAssertTrue(bindings.bindings(for: try command("focus left")).isEmpty)
        XCTAssertEqual(bindings.unshown.count, 1)
        XCTAssertEqual(bindings.unshown[0].commands.count, 2)
    }

    func testTapAndSequenceBindingsHaveTextLabelsAndRemainExecutable() throws {
        var bindings = ActionMenuBindings(mode: try mode("""
        [mode.main.binding]
        esc-h = 'focus left'
        [mode.main.binding-tap]
        left-alt = 'focus left'
        """))
        let matches = bindings.bindings(for: try command("focus left"))
        XCTAssertEqual(matches.count, 2)
        XCTAssertTrue(matches.allSatisfy { $0.keyEquivalent == nil && $0.commands.count == 1 })
        XCTAssertTrue(matches.contains { $0.notation.hasPrefix("Tap ") })
        XCTAssertTrue(matches.contains { $0.notation.hasPrefix("Sequence ") })
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testCustomExecIsPreservedInOtherBindings() throws {
        let bindings = ActionMenuBindings(mode: try mode("[mode.main.binding]\nalt-enter = 'exec-and-forget open -a Ghostty'"))
        XCTAssertEqual(bindings.unshown.count, 1)
        XCTAssertTrue(bindings.unshown[0].commands[0] is ExecAndForgetCommand)
    }

    func testCurrentModeDoesNotLeakMainBindings() throws {
        let current = try mode("""
        [mode.main.binding]
        alt-left = 'focus left'
        [mode.grouping.binding]
        left = ['join-with left', 'mode main']
        """, name: "grouping")
        var bindings = ActionMenuBindings(mode: current)
        XCTAssertTrue(bindings.bindings(for: try command("focus left")).isEmpty)
        XCTAssertEqual(bindings.unshown.map(\.notation), ["left"])
    }

    func testNewSnapshotReflectsReloadedBindings() throws {
        let old = try mode("[mode.main.binding]\nalt-left = 'focus left'")
        let new = try mode("[mode.main.binding]\nctrl-left = 'focus left'")
        XCTAssertEqual(ActionMenuBindings(mode: old).entries[0].modifiers, .option)
        XCTAssertEqual(ActionMenuBindings(mode: new).entries[0].modifiers, .control)
    }

    func testNoModeStillAllowsCatalogWithoutShortcuts() throws {
        var bindings = ActionMenuBindings(mode: nil)
        XCTAssertTrue(bindings.bindings(for: try command("scrolling-center")).isEmpty)
        XCTAssertTrue(bindings.unshown.isEmpty)
    }

    func testWindowRequirementsDistinguishWorkspaceAndWindowActions() throws {
        for script in ["focus left", "join-with left", "fullscreen", "move-node-to-workspace 2"] {
            XCTAssertTrue(menuCommandRequiresWindow(try command(script)))
        }
        for script in ["workspace 2", "mode main", "enable toggle", "reload-config", "focus-monitor main"] {
            XCTAssertFalse(menuCommandRequiresWindow(try command(script)))
        }
    }

    func testNativeKeyEquivalents() {
        XCTAssertEqual(menuKeyEquivalent(.a), "a")
        XCTAssertEqual(menuKeyEquivalent(.space), " ")
        XCTAssertEqual(menuKeyEquivalent(.f12), String(UnicodeScalar(NSF1FunctionKey + 11)!))
        XCTAssertEqual(menuKeyEquivalent(.leftBracket), "[")
        XCTAssertEqual(menuKeyEquivalent(.pageUp), String(UnicodeScalar(NSPageUpFunctionKey)!))
        XCTAssertEqual(menuKeyEquivalent(.forwardDelete), String(UnicodeScalar(NSDeleteFunctionKey)!))
    }

    func testPotentialConflictsAreDeduplicatedAndExcludeWinMux() {
        XCTAssertEqual(otherTilingManagers(["com.brnbw.dinky", "com.brnbw.dinky", "com.knollsoft.Rectangle", "com.winmux.app", "com.apple.finder"]), ["Dinky", "Rectangle"])
        XCTAssertTrue(otherTilingManagers([]).isEmpty)
    }

    func testProcessConflictsIncludeDaemonsAndIgnoreUnrelatedProcesses() {
        XCTAssertEqual(otherTilingManagerProcesses(["AeroSpace", "aerospace", "yabai", "KiwiDesk", "Dinky", "WinMux", "Dock"]), ["AeroSpace", "Dinky", "KiwiDesk", "yabai"])
        XCTAssertTrue(otherTilingManagerProcesses([]).isEmpty)
    }

    func testMenuWithoutWindowDisablesLayoutButAllowsWorkspaceAndSettings() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = previousEnabled }
        TrayMenuModel.shared.isEnabled = true
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertFalse(try XCTUnwrap(menu.items.first { $0.title == "Fullscreen" }).isEnabled)
        let workspaces = try submenu("Spaces", in: try submenu("Commands", in: menu))
        XCTAssertTrue(try XCTUnwrap(workspaces.items.first { $0.title == "Next" }).isEnabled)
        XCTAssertTrue(try XCTUnwrap(menu.items.first { $0.title == "Settings…" }).isEnabled)
    }

    func testMenuShowsShortcutWarningWhenSideFilteredHandlingIsUnavailable() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        let previousHealth = TrayMenuModel.shared.shortcutHealth
        defer {
            TrayMenuModel.shared.isEnabled = previousEnabled
            TrayMenuModel.shared.shortcutHealth = previousHealth
        }
        TrayMenuModel.shared.isEnabled = true
        TrayMenuModel.shared.shortcutHealth = .unavailable
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "⚠ Some keyboard shortcuts are unavailable" })
        XCTAssertTrue(menu.items.contains { $0.title == "View shortcut diagnostics…" })
    }

    func testDisabledMenuKeepsEssentialControlsAvailable() throws {
        let previousEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = previousEnabled }
        TrayMenuModel.shared.isEnabled = false
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        for title in ["Enabled", "Settings…", "Quit StripMuxX"] {
            XCTAssertTrue(try XCTUnwrap(menu.items.first { $0.title == title }).isEnabled, title)
        }
        let commands = try submenu("Commands", in: menu)
        XCTAssertTrue(try XCTUnwrap(commands.items.first { $0.title == "Reload Config" }).isEnabled)
        let workspaces = try submenu("Spaces", in: commands)
        XCTAssertFalse(try XCTUnwrap(workspaces.items.first { $0.title == "Next" }).isEnabled)
    }

    func testMenuReflectsModeAndConfigurationOnEveryOpening() throws {
        let oldMode = activeMode
        defer { activeMode = oldMode }
        config.modes["main"] = try mode("[mode.main.binding]\nalt-space = 'scrolling-center'")
        activeMode = "main"
        let menu = NSMenu()
        let controller = NativeActionMenu()
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Center Column" }).keyEquivalent, " ")
        activeMode = "grouping"
        config.modes["grouping"] = .zero
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.title == "Center Column" }).keyEquivalent, "")
        XCTAssertTrue(menu.items.contains { $0.title == "Mode: grouping" })
    }

    func testDiagnosticsIdentifiesMissingFile() async {
        let originalUrl = configUrl
        defer { configUrl = originalUrl }
        configUrl = projectRoot.appendingPathComponent("missing-\(UUID().uuidString).toml")
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("file is missing"), report)
    }

    func testReportHasWhatTheInstallerChecks() async {
        let report = await buildDiagnosticsReport()
        XCTAssertTrue(report.contains("  accessibility: "))
        XCTAssertTrue(report.contains("  screen capture: "))
        XCTAssertTrue(report.contains("loaded: \(configUrl.path)"))
    }

}
