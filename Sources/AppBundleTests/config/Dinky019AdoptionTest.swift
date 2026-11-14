@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class Dinky019AdoptionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { setUpWorkspacesForTests() }

    func testModifierAliasesUseExistingChordIdentityAndSideFilter() throws {
        let aliases = parseConfig("""
            [modifiers]
            alt = 'left'
            [mode.main.binding]
            hyper-1 = 'workspace 1'
            meh-2 = 'workspace 2'
            """)
        XCTAssertTrue(aliases.errors.isEmpty, "\(aliases.errors)")
        let bindings = try XCTUnwrap(aliases.config.modes["main"]).bindings.values
        XCTAssertEqual(bindings.count, 2)
        let hyper = try parseBinding("hyper-1", .emptyRoot, config.keyMapping.resolve()).get()
        let expanded = try parseBinding("alt-ctrl-cmd-shift-1", .emptyRoot, config.keyMapping.resolve()).get()
        XCTAssertEqual(hyper.0, expanded.0)
        XCTAssertEqual(hyper.1, expanded.1)
        XCTAssertTrue(aliases.config.modifierSides.restricts(hyper.0))
        for (alias, full) in [("hyper", "alt-ctrl-cmd-shift"), ("meh", "alt-ctrl-shift")] {
            let duplicate = parseConfig("[mode.main.binding]\n\(alias)-1 = 'workspace 1'\n\(full)-1 = 'workspace 2'")
            XCTAssertTrue(duplicate.errors.contains { $0.description.contains("redeclaration") })
        }
        XCTAssertFalse(parseConfig("[mode.main.binding]\nsuper-1 = 'workspace 1'").errors.isEmpty)
    }

    func testBundleIdRegexIsCaseInsensitiveAndConjunctiveWithExactId() async throws {
        let text = """
            [[on-window-detected]]
            if.app-id-regex = '^BOBKO\\.WinMux\\.'
            if.app-id = 'bobko.WinMux.test-app'
            run = 'layout tiling'
            """
        let parsed = parseConfig(text)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        var callback = try XCTUnwrap(parsed.config.onWindowDetected.first)
        let window = TestWindow.new(id: 99001, parent: focus.workspace.rootTilingContainer)
        let matches = try await callback.matches(window)
        XCTAssertTrue(matches)
        callback.matcher.appId = "another.app"
        let wrongExact = try await callback.matches(window)
        XCTAssertFalse(wrongExact)
        callback.matcher.appId = nil
        callback.matcher.appIdRegex = try Regex("^com\\.jetbrains\\.")
        let wrongRegex = try await callback.matches(window)
        XCTAssertFalse(wrongRegex)
        XCTAssertFalse(parseConfig("[[on-window-detected]]\nif.app-id-regex = '['\nrun = 'layout tiling'").errors.isEmpty)
    }

    func testRuleEditorPreservesAndEditsBundleIdRegex() throws {
        let block = """
            [[on-window-detected]]
            # family of applications
            if.app-id-regex = '^com\\.jetbrains\\.'
            run = ['layout tiling']
            """
        let original = try SettingsRuleDraft(block: block)
        XCTAssertEqual(original.appIdRegex, "^com\\.jetbrains\\.")
        var changed = original
        changed.appIdRegex = "^com\\.apple\\."
        let edited = try SettingsRuleDocument.editing(block, edits: changed.edits(from: original))
        XCTAssertTrue(edited.contains("# family of applications"))
        XCTAssertEqual(try SettingsRuleDraft(block: edited).appIdRegex, changed.appIdRegex)
        XCTAssertTrue(parseConfig(edited).errors.isEmpty)
        XCTAssertTrue(SettingsRuleRow(id: 0, block: edited).matches.contains(changed.appIdRegex))
    }

    func testHookPathKeepsConfiguredVariablesAndHandlesFinderEnvironment() {
        let finder = execEnvironment([:], context: ["WINMUX_DISPLAYS": "2"], cliDirectory: "/Applications/StripMuxX.app/Contents/Helpers")
        XCTAssertEqual(finder["PATH"], "/Applications/StripMuxX.app/Contents/Helpers:/usr/bin:/bin:/usr/sbin:/sbin")
        XCTAssertEqual(finder["WINMUX_DISPLAYS"], "2")
        let custom = execEnvironment(["PATH": "/custom/bin", "KEEP": "yes"], context: [:], cliDirectory: "/bundle/Helpers")
        XCTAssertEqual(custom["PATH"], "/bundle/Helpers:/custom/bin")
        XCTAssertEqual(custom["KEEP"], "yes")
        XCTAssertEqual(execEnvironment(["PATH": "/custom/bin"], context: [:], cliDirectory: nil), ["PATH": "/custom/bin"])
    }

    func testCommandsSucceedAtAnEdgeButKeepExplicitFailAndFloatingErrors() async throws {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 99003, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        for command in ["move --boundaries-action stop left", "join-with left", "resize height +10"] {
            let result = try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode, 0, command + result.stderr.joined())
        }
        let failure = try await parseCommand("move --boundaries-action fail left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(failure.exitCode, 1)
        window.bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        let floating = try await parseCommand("resize width +10").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(floating.exitCode, 1)
        let floatingJoin = try await parseCommand("join-with left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(floatingJoin.exitCode, 1)
    }

}
