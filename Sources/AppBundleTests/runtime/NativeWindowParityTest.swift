import Common
import XCTest
@testable import AppBundle

@MainActor
final class NativeWindowParityTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        nativeSkippedWindowRuleCommands = []
    }

    func testPerWindowActionsAreNativeCommands() throws {
        for script in ["fullscreen", "macos-native-fullscreen", "macos-native-minimize", "close", "close-all-windows-but-current"] {
            let command = try XCTUnwrap(parseCommand(script).cmdOrNil, script)
            XCTAssertTrue(runtime.native.accepts(command), script)
        }
    }

    func testRulesFloatOrTileNewWindowsAndReportWhatTheySkip() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = ['layout floating', 'move-node-to-monitor 2']
        """).config.onWindowDetected
        let workspace = Workspace.get(byName: "native-desktop")
        let window = TestWindow.new(id: 40, parent: workspace.rootTilingContainer)
        try await applyNativeWindowDetectedRules(window) { true }
        XCTAssertTrue(window.parent === workspace, "Floated on its own desktop")
        XCTAssertEqual(nativeSkippedWindowRuleCommands, ["move-node-to-monitor 2"])
    }

    func testRulesSetANewWindowsColumnWidthByShareOrPoints() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        if.window-title-regex-substring = 'share'
        run = 'scrolling-width 0.4'
        [[on-window-detected]]
        if.window-title-regex-substring = 'points'
        run = ['scrolling-width-pixels 900', 'scrolling-width next']
        """).config.onWindowDetected
        let workspace = Workspace.get(byName: "native-desktop")
        let share = TestWindow.new(id: 60, parent: workspace.rootTilingContainer)
        share.testTitle = "share"
        let points = TestWindow.new(id: 61, parent: workspace.rootTilingContainer)
        points.testTitle = "points"
        _ = TestWindow.new(id: 62, parent: workspace.rootTilingContainer).focusWindow()
        try await applyNativeWindowDetectedRules(share) { true }
        try await applyNativeWindowDetectedRules(points) { true }
        XCTAssertEqual(share.scrollingColumnWidth, 0.4)
        XCTAssertNil(share.scrollingColumnFixedWidth)
        XCTAssertEqual(points.scrollingColumnFixedWidth, 900)
        XCTAssertNil(focus.windowOrNil?.scrollingColumnFixedWidth, "Only the new window's column changes")
        XCTAssertEqual(nativeSkippedWindowRuleCommands, ["scrolling-width next"])
    }

    func testScrollingWidthTakesAShareOfTheDisplay() {
        XCTAssertEqual((parseCommand("scrolling-width 0.4").cmdOrNil as? ScrollingWidthCommand)?.args.target.val, .share(0.4))
        XCTAssertNil(parseCommand("scrolling-width 1.5").cmdOrNil, "More than the display")
        XCTAssertNil(parseCommand("scrolling-width wide").cmdOrNil)
    }

    func testRulesLeaveAWindowWhoseOwnershipChangedDuringMatching() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = 'layout floating'
        """).config.onWindowDetected
        let workspace = Workspace.get(byName: "native-desktop")
        let window = TestWindow.new(id: 41, parent: workspace.rootTilingContainer)
        try await applyNativeWindowDetectedRules(window) { false }
        XCTAssertTrue(window.parent === workspace.rootTilingContainer)
    }

    func testMoveRulesSkipWindowsThatExistedAtLaunchEvenWhenFirstSeenLater() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = 'move-node-to-workspace 3'
        """).config.onWindowDetected
        var scheduled: [UInt32] = []
        let original = nativeRuleMoveScheduler
        nativeRuleMoveScheduler = { _, id in scheduled.append(id) }
        defer { nativeRuleMoveScheduler = original }
        runtime.native.windowsPresentAtLaunch = [50]
        let workspace = Workspace.get(byName: "native-desktop")
        try await applyNativeWindowDetectedRules(TestWindow.new(id: 50, parent: workspace.rootTilingContainer)) { true }
        try await applyNativeWindowDetectedRules(TestWindow.new(id: 51, parent: workspace.rootTilingContainer)) { true }
        XCTAssertEqual(scheduled, [51], "Only the window opened after launch moves")
    }
}
