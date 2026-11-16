import Common
import NativeSpaces

// Desktops as users and scripts see them: numbered in macOS Control-N order,
// never by the internal `__native_space_<uuid>` workspace names.

/// The last observation stays listed during a read, so lists don't flicker away.
@MainActor
func nativeObservedDisplays() -> [NativeSpaceDisplay]? {
    let native = runtime.native
    return (native.observation?.inventory.lastSnapshot ?? native.layouts.snapshot)?.displays
}

/// Desktops in Control-N order with the workspace holding each one's layout.
@MainActor
func nativeDesktopWorkspaces() -> [(number: Int, workspace: Workspace)] {
    let layouts = runtime.native.layouts
    var result: [(number: Int, workspace: Workspace)] = []
    var number = 0
    for display in nativeObservedDisplays() ?? [] {
        for space in display.spaces where space.isDesktop {
            number += 1
            if let uuid = space.uuid, let workspace = layouts.retainedByUUID[uuid] { result.append((number, workspace)) }
        }
    }
    return result
}

@MainActor
func nativeDesktopNumber(of workspace: Workspace) -> Int? {
    nativeDesktopWorkspaces().first { $0.workspace === workspace }?.number
}

/// The name scripts and queries see: the desktop number.
@MainActor
func userFacingWorkspaceName(_ workspace: Workspace) -> String {
    nativeDesktopNumber(of: workspace).map(String.init) ?? workspace.name
}

/// Resolves a workspace name typed by a user: a desktop number.
@MainActor
func userWorkspace(named name: String) -> Workspace? {
    Int(name).flatMap { number in nativeDesktopWorkspaces().first { $0.number == number }?.workspace }
}

@MainActor
func userFacingDesktopName(_ workspace: Workspace) -> String {
    nativeDesktopNumber(of: workspace).map { nativeDesktopDisplayName($0) } ?? "The space"
}

/// Native snapshots name the main display "Main" when it has no UUID of its own.
@MainActor
func nativeDisplay(_ display: NativeSpaceDisplay, isShownOn monitor: Monitor) -> Bool {
    display.identifier == "Main" ? monitor.rect.topLeftCorner == mainMonitor.rect.topLeftCorner : display.identifier == monitor.displayUUID
}

/// The desktop a display shows, or nil while it shows a fullscreen Space or is not observed.
@MainActor
func nativeActiveDesktop(on monitor: Monitor) -> Workspace? {
    guard let display = nativeObservedDisplays()?.first(where: { nativeDisplay($0, isShownOn: monitor) }) else { return nil }
    return runtime.native.layouts.activeWorkspace(on: display.identifier)
}

/// `focus-monitor`: focuses the most recent window of the desktop that display shows.
@MainActor
func nativeFocusMonitor(_ args: FocusMonitorCmdArgs, env: CmdEnv, io: CmdIo) -> Bool {
    guard let target = args.resolveTargetOrReportError(env, io) else { return false }
    switch args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround) {
        case .success(let monitor):
            guard let desktop = nativeActiveDesktop(on: monitor) else { return io.err("\(monitor.name) shows no space") }
            guard let window = desktop.mostRecentWindowRecursive else {
                return io.err("\(nativeDesktopNumber(of: desktop).map { nativeDesktopDisplayName($0) } ?? "The space") on \(monitor.name) has no window to focus")
            }
            guard window.focusWindow() else { return io.err("Window \(window.windowId) could not take focus") }
            window.nativeFocus()
            return true
        case .failure(let message):
            return io.err(message)
    }
}

func nativeDesktopDisplayName(_ number: Int) -> String { "Space \(number)" }

/// Commands that bring a window forward: switch to its desktop when that desktop
/// isn't showing, then focus it.
@MainActor
func nativeFocusWindowCommands(_ windowId: UInt32) -> [String] {
    var commands: [String] = []
    if let workspace = Window.get(byId: windowId)?.nodeWorkspace, !workspace.isVisible,
       let number = nativeDesktopNumber(of: workspace) {
        commands.append("workspace \(number)")
    }
    commands.append("focus --window-id \(windowId)")
    return commands
}

/// Brings a window forward, switching to its desktop first; returns an error to show.
@MainActor
func focusNativeWindow(_ windowId: UInt32) async throws -> String? {
    try await runUserCommands(nativeFocusWindowCommands(windowId))
}
