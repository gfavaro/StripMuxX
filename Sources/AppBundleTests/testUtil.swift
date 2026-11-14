@testable import AppBundle
@testable import NativeSpaces
import Common
import Foundation
import HotKey
import XCTest

struct TestMonitor: Monitor {
    var hardwareIdentity: MonitorHardwareIdentity? = nil
    var displayUUID: String? = nil
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

let projectRoot: URL = {
    var url = URL(filePath: #filePath).absoluteURL
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    return url
}()

/// A fresh runtime whose observation shows one display, `display-1`, on desktop 1 of
/// `desktops`. Returns the desktops' workspaces in Control-N order; focus is on the first.
@MainActor
@discardableResult
func setUpWorkspacesForTests(desktops: Int = 1) -> [Workspace] {
    layoutForNextDetectedWindow = nil
    LayoutUndoHistory.shared.reset()
    for workspace in Workspace.all {
        for child in workspace.children {
            child.unbindFromParent()
        }
    }

    WinMuxRuntime.replaceForTests()
    testSnapshot = nil
    resetCachedWindowTitles()

    // Don't create any bindings for tests
    config.modes = [mainModeId: Mode(bindings: [:], tapBindings: [:])]
    config.persistentWorkspaces = []

    let workspaces = observeTestDesktops([(display: "display-1", desktops: desktops, active: 0)])[0]
    check(workspaces[0].focusWorkspace())
    runtime.native.tiling.assumeReconciledForTests()
    TestApp.shared.focusedWindow = nil
    TestApp.shared.windows = []
    return workspaces
}

/// Publishes an observation of these displays, side by side, 1920 × 1080 each, and makes
/// them the test monitors. Desktop UUIDs are `<display>-desktop-<n>`, so the same layout
/// observed again keeps each desktop's workspace. Returns each display's workspaces.
@MainActor
@discardableResult
func observeTestDesktops(_ layout: [(display: String, desktops: Int, active: Int)],
                         windows: [NativeWindowMembership] = []) -> [[Workspace]] {
    let monitors = layout.indices.map { index in
        let rect = Rect(topLeftX: Double(index * 1920), topLeftY: 0, width: 1920, height: 1080)
        return TestMonitor(displayUUID: layout[index].display, monitorAppKitNsScreenScreensId: index + 1,
                           name: "Display\(index + 1)", rect: rect, visibleRect: rect, isMain: index == 0)
    }
    setMonitorsForTests(monitors)
    var nextSpaceID = 1
    let displays = layout.map { item -> NativeSpaceDisplay in
        let spaces = (0..<item.desktops).map { number -> NativeSpace in
            defer { nextSpaceID += 1 }
            return NativeSpace(id: String(nextSpaceID), uuid: "\(item.display)-desktop-\(number + 1)", type: 0)
        }
        return NativeSpaceDisplay(identifier: item.display, activeSpaceID: spaces[item.active].id, spaces: spaces)
    }
    let snapshot = NativeSpacesSnapshot(displays: displays, windows: windows, readMilliseconds: 0, capturedAt: .now)
    publishTestSnapshot(snapshot, monitors: monitors)
    let result = displays.map { display in
        display.spaces.map { runtime.native.layouts.retainedByUUID[$0.uuid!]! }
    }
    observeTestWindowMemberships()
    return result
}

@MainActor private var testSnapshot: (snapshot: NativeSpacesSnapshot, monitors: [Monitor])?

@MainActor private func publishTestSnapshot(_ snapshot: NativeSpacesSnapshot, monitors: [Monitor]) {
    var inventory = NativeWorkspaceInventory()
    check(inventory.publish(snapshot, for: inventory.invalidate()))
    runtime.native.layouts.reconcile(inventory, displays: monitors)
    testSnapshot = (snapshot, monitors)
}

/// While the observation is the one `observeTestDesktops` published, WindowServer reports
/// every test window on the desktop whose tree holds it, as it would for real windows.
/// A test that publishes its own observation keeps it as it is.
@MainActor
func observeTestWindowMemberships() {
    guard let current = testSnapshot, runtime.native.layouts.snapshot == current.snapshot else { return }
    let spaceOf = Dictionary(runtime.native.layouts.currentBySpaceID.map { (ObjectIdentifier($0.value), $0.key) },
                             uniquingKeysWith: { first, _ in first })
    let windows = Workspace.all.flatMap { workspace in
        (workspace.allLeafWindowsRecursive).compactMap { window in
            spaceOf[ObjectIdentifier(workspace)].map { NativeWindowMembership(windowID: window.windowId, spaceIDs: [$0]) }
        }
    }
    guard windows != current.snapshot.windows else { return }
    publishTestSnapshot(NativeSpacesSnapshot(displays: current.snapshot.displays, windows: windows,
                                             readMilliseconds: 0, capturedAt: current.snapshot.capturedAt),
                        monitors: current.monitors)
}

extension ParsedCmd {
    var errorOrNil: String? {
        if case .failure(let e) = self {
            return e
        } else {
            return nil
        }
    }

    var cmdOrDie: T { cmdOrNil ?? dieT() }
}

func testParseCommandFail(_ command: String, msg expected: String, file: StaticString = #filePath, line: UInt = #line) {
    let parsed = parseCommand(command)
    switch parsed {
        case .cmd(let command): XCTFail("\(command) isn't supposed to be parseable", file: file, line: line)
        case .failure(let msg): assertEquals(msg, expected, file: file, line: line)
        case .help: XCTFail("Expected parse failure, got help", file: file, line: line)
    }
}

extension WorkspaceCmdArgs {
    init(target: WorkspaceTarget, autoBackAndForth: Bool? = nil, wrapAround: Bool? = nil) {
        self = WorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._autoBackAndForth = autoBackAndForth
        self._wrapAround = wrapAround
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    init(target: WorkspaceTarget, wrapAround: Bool? = nil) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._wrapAround = wrapAround
    }

    init(workspace: String) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(.direct(.parse(workspace).getOrDie()))
    }
}

extension HotkeyBinding {
    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: [any Command]) {
        let descriptionWithKeyNotation = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.init(modifiers, keyCode, commands, descriptionWithKeyNotation: descriptionWithKeyNotation)
    }
}

/// The desktop the runtime records a display as showing.
@MainActor
func shownWorkspace(on monitor: Monitor) -> Workspace? {
    runtime.workspaces.monitorViewportsById[MonitorViewportId(monitor)]?.activeWorkspaceId.flatMap { runtime.workspaces.workspaceById[$0] }
}
