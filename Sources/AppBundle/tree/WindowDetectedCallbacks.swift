import AppKit
import Common

/// Commands that send a window to another desktop or display.
@MainActor
func isWindowRelocation(_ command: any Command) -> Bool {
    command is MoveNodeToWorkspaceCommand || command is MoveNodeToMonitorCommand
}

/// A rule's commands for this window. An app-wide routing rule is for the app's ordinary
/// windows: sending its dialog (a save panel, a print or format sheet) to another
/// workspace left the app stuck behind a modal no one could see (WinMux issue #23).
/// Floating and tiling still apply to dialogs.
@MainActor
func windowRuleCommands(_ commands: [any Command], isDialog: Bool) -> [any Command] {
    isDialog ? commands.filter { !isWindowRelocation($0) } : commands
}

/// Asked only when a matching rule would relocate the window, and at most once.
@MainActor
private final class WindowRuleDialogCheck {
    private let window: Window
    private var answer: Bool?
    init(_ window: Window) { self.window = window }
    func isDialog(for commands: [any Command]) async -> Bool {
        guard commands.contains(where: isWindowRelocation) else { return false }
        if let answer { return answer }
        let result = (try? await (window as? MacWindow)?.isDialogHeuristic(getWindowLevel(for: window.windowId))) ?? false
        answer = result
        return result
    }
}

/// Rule commands that were skipped, for doctor. Windows register during reconciliation,
/// before commands can run, so rules apply only what makes sense for a new window:
/// floating or tiling it, and moving it to a desktop.
@MainActor var nativeSkippedWindowRuleCommands: Set<String> = []
/// Schedules a rule's move for a window opened after launch; tests replace it.
@MainActor var nativeRuleMoveScheduler: (MoveNodeToWorkspaceCommand, UInt32) -> Void = { scheduleNativeRuleMove($0, window: $1) }

@MainActor
func applyNativeWindowDetectedRules(_ window: Window, stillOwned: () -> Bool) async throws {
    let dialog = WindowRuleDialogCheck(window)
    for callback in config.onWindowDetected where try await callback.matches(window) {
        guard stillOwned() else { return }
        let commands = windowRuleCommands(callback.run, isDialog: await dialog.isDialog(for: callback.run))
        guard stillOwned() else { return }
        for command in commands {
            if let move = command as? MoveNodeToWorkspaceCommand, runtime.native.accepts(move) {
                // Existing windows stay put, including ones first seen when their desktop is
                // visited later; only windows opened after launch are moved.
                if !runtime.native.windowsPresentAtLaunch.contains(window.windowId) {
                    nativeRuleMoveScheduler(move, window.windowId)
                }
                continue
            }
            if applyRuleColumnWidth(command, to: window) { continue }
            guard let layout = command as? LayoutCommand, !layout.args.forNextDetectedWindow,
                  let target = layout.args.toggleBetween.val.first(where: { $0 == .floating || $0 == .tiling }) else {
                nativeSkippedWindowRuleCommands.insert("\(command.args)")
                continue
            }
            if target == .floating, let workspace = window.nodeWorkspace {
                window.floatedByDetection = false // A rule chose it.
                window.bindAsFloatingWindow(to: workspace)
            }
        }
        if !callback.checkFurtherCallbacks { return }
    }
}

/// Runs after registration finishes, once native tiling is ready to resolve the window.
@MainActor
private func scheduleNativeRuleMove(_ move: MoveNodeToWorkspaceCommand, window id: UInt32) {
    let owner = runtime
    owner.task {
        _ = await owner.native.tiling.waitUntilReady(timeout: .seconds(2))
        let io = CmdIo(stdin: .emptyStdin)
        if !(await owner.native.windowMoves.transferWindow(move.args, env: .defaultEnv.copy(\.windowId, id), io: io)) {
            // One entry per rule, keeping its latest failure, so the set stays bounded.
            let rule = "\(move.args)"
            nativeSkippedWindowRuleCommands = nativeSkippedWindowRuleCommands.filter { !$0.hasPrefix(rule + " (failed") }
            nativeSkippedWindowRuleCommands.insert("\(rule) (failed: \(io.stderr.last ?? "unknown"))")
        }
    }
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let startupMatcher = matcher.duringWinMuxStartup, startupMatcher != isStartup {
            return false
        }
        if let regex = matcher.windowTitleRegexSubstring, !(try await window.title).contains(regex) {
            return false
        }
        if let appId = matcher.appId, appId != window.app.rawAppBundleId {
            return false
        }
        if let regex = matcher.appIdRegex, !(window.app.rawAppBundleId ?? "").contains(regex) {
            return false
        }
        if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(regex) {
            return false
        }
        if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
            return false
        }
        if let wanted = matcher.appHasOtherWindows, wanted != appHasOtherWindows(window) {
            return false
        }
        return true
    }
}

/// Whether another window of the window's app is managed, on any desktop, minimized ones
/// included. A launching app's first window has none; a login or dialog window opened
/// later has its main window.
@MainActor
func appHasOtherWindows(_ window: Window) -> Bool {
    func isOther(_ candidate: Window) -> Bool { candidate !== window && candidate.app.pid == window.app.pid }
    return Workspace.all.contains { $0.allLeafWindowsRecursive.contains(where: isOther) }
}

/// A rule's `scrolling-width` or `scrolling-width-pixels` sets the new window's own column,
/// whatever is focused. Windows in a stack or floating are left alone.
@MainActor
func applyRuleColumnWidth(_ command: any Command, to window: Window) -> Bool {
    let width: (share: CGFloat?, points: CGFloat?)
    switch command {
        case let command as ScrollingWidthCommand:
            switch command.args.target.val {
                case .share(let share): width = (CGFloat(share), nil)
                case .action(.full): width = (1, nil)
                case .action: return false // Stepping presets means nothing for a window just opened.
            }
        case let command as ScrollingWidthPixelsCommand: width = (nil, CGFloat(command.args.points.val))
        default: return false
    }
    guard window.parent is TilingContainer, window.topLevelWorkspaceGroup === window else { return true }
    window.scrollingColumnWidth = width.share
    window.scrollingColumnFixedWidth = width.points
    return true
}
