import AppKit
import Common

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: WinMuxAny, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor fileprivate var frozen: FrozenFocus {
        FrozenFocus(windowId: windowOrNil?.windowId, workspaceName: workspace.name, workspaceId: workspace.id)
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// The window - workspace relation could change since the moment object was created
struct FrozenFocus: WinMuxAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    let workspaceId: WorkspaceId

    @MainActor var liveOrNil: LiveFocus? {
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        guard let workspace = Workspace.existing(byName: workspaceName), workspace.id == workspaceId else { return nil }

        let workspaceFocus = workspace.toLiveFocus()
        let windowFocus = window?.takeIf(\.participatesInWorkspaceFocus)?.toLiveFocusOrNil() ?? workspaceFocus

        return workspaceFocus.workspace != windowFocus.workspace
            ? workspaceFocus // If window and workspace become separated prefer workspace
            : windowFocus
    }

    @MainActor var live: LiveFocus { liveOrNil ?? unobservedWorkspace.toLiveFocus() }
}

/// What focus resolves to before the first observation names a desktop. It holds no windows.
@MainActor private var unobservedWorkspace: Workspace { Workspace.get(byName: "__unobserved") }

func debugDescribe(_ focus: LiveFocus?) -> String {
    guard let focus else { return "nil" }
    return "w:\(focus.windowOrNil?.windowId.description ?? "nil") ws:\(focus.workspace.name)"
}

@MainActor
final class WorkspaceFocusState {
    lazy var requested: FrozenFocus = unobservedWorkspace.toLiveFocus().frozen
    lazy var lastKnown: FrozenFocus = requested
}

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, WINMUX_WINDOW_ID env and
/// WINMUX_WORKSPACE env before accessing the global focus.
@MainActor var focus: LiveFocus { runtime.focus.requested.live }

/// Unlike derived live focus, this changes only when focus is explicitly assigned.
@MainActor func captureRequestedFocus() -> FrozenFocus { runtime.focus.requested }

enum FocusChangeOrigin: Equatable { case explicit, native }

/// Focus can only go to a showing desktop, and to a window macOS currently presents.
@MainActor func setFocus(to newFocus: LiveFocus, origin: FocusChangeOrigin = .explicit) -> Bool {
    let layouts = runtime.native.layouts
    guard let snapshot = layouts.snapshot,
          snapshot.displays.contains(where: { layouts.activeWorkspace(on: $0.identifier) === newFocus.workspace }),
          newFocus.windowOrNil?.nativeLayoutEligible != false else { return false }
    let workspace = newFocus.workspace
    if let candidate = newFocus.windowOrNil,
       workspace.lastFocusedWindow !== candidate {
        workspace.previousFocusedWindow = workspace.lastFocusedWindow
        workspace.lastFocusedWindow = candidate
    }
    runtime.focus.requested = newFocus.frozen
    if origin == .native { runtime.focus.lastKnown = newFocus.frozen }
    newFocus.windowOrNil?.markAsMostRecentChild()
    return true
}

/// Choose a logical focus fallback *only* if the closed window was still
/// requested. Never activate apps, move Spaces or fight a newer native focus.
@MainActor
@discardableResult
func restoreLogicalFocusAfterWindowClosed(_ closedID: UInt32, in workspace: Workspace) -> Bool {
    guard runtime.focus.requested.windowId == closedID, workspace.isVisible else { return false }
    let eligible = workspace.allLeafWindowsRecursive.filter {
        $0.windowId != closedID && $0.nativeLayoutEligible && $0.participatesInWorkspaceFocus
    }
    guard !eligible.isEmpty else { return false }
    let preferred = eligible.first(where: { $0 === workspace.previousFocusedWindow })
    let chosen = preferred ?? eligible.first(where: { $0 === workspace.mostRecentWorkspaceFocusableWindowRecursive }) ?? eligible[0]
    return setFocus(to: LiveFocus(windowOrNil: chosen, workspace: workspace), origin: .native)
}

extension Window {
    @MainActor func focusWindow() -> Bool {
        toLiveFocusOrNil().map { setFocus(to: $0) } ?? false
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? { nodeWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}

extension Workspace {
    @MainActor func focusWorkspace() -> Bool {
        setFocus(to: toLiveFocus())
    }

    func toLiveFocus() -> LiveFocus {
        LiveFocus(windowOrNil: mostRecentWorkspaceFocusableWindowRecursive, workspace: self)
    }
}

/// `exec-on-workspace-change`
@MainActor func runExecOnWorkspaceChange(new newWorkspace: String, previous oldWorkspace: String) {
    guard let exec = config.execOnWorkspaceChange.first else { return }
    let process = Process()
    process.executableURL = URL(filePath: exec)
    process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
    var environment = config.execConfig.envVariables + hookEnvironment(event: "focused-workspace-changed").asMap
    environment[WINMUX_FOCUSED_WORKSPACE] = newWorkspace
    environment[WINMUX_PREV_WORKSPACE] = oldWorkspace
    environment[WINMUX_WORKSPACE] = newWorkspace
    process.environment = environment
    _ = Result { try process.run() }
}
