import AppKit
import Common

struct UndoLayoutCommand: Command {
    let args: UndoLayoutCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard LayoutUndoHistory.shared.undo(target.workspace) else {
            return io.err("Nothing to undo on this space")
        }
        return true
    }
}

/// The focused desktop's strip before each command that changed it, newest last, so
/// `undo-layout` can put it back. Undo only rearranges windows still on the desktop: one
/// closed or moved away since is left where it is, and one that arrived since joins the
/// end of the restored strip.
@MainActor
final class LayoutUndoHistory {
    static let shared = LayoutUndoHistory()
    private static let limit = 20
    /// By workspace name, which is the desktop's identity.
    private var entries: [String: [FrozenStrip]] = [:]

    static func records(_ command: any Command) -> Bool {
        switch command {
            case is LayoutCommand, is MoveCommand, is SwapCommand, is JoinWithCommand, is FlattenWorkspaceTreeCommand,
                 is BalanceSizesCommand, is ResizeCommand, is ScrollingWidthCommand, is ScrollingMoveCommand,
                 is ScrollingPinCommand:
                true
            default:
                false
        }
    }

    /// The state to compare with after `command`, when it is one undo covers.
    func before(_ command: any Command) -> (Workspace, FrozenStrip)? {
        Self.records(command) ? (focus.workspace, FrozenStrip(focus.workspace)) : nil
    }

    func commandFinished(_ before: (Workspace, FrozenStrip)) {
        let (workspace, frozen) = before
        guard FrozenStrip(workspace) != frozen else { return }
        entries[workspace.name, default: []].append(frozen)
        if entries[workspace.name]!.count > Self.limit { entries[workspace.name]!.removeFirst() }
    }

    func undo(_ workspace: Workspace) -> Bool {
        guard let frozen = entries[workspace.name]?.popLast() else { return false }
        let windows = workspace.allLeafWindowsRecursive
        restoreStrip(frozen, to: workspace, windowsById: Dictionary(windows.map { ($0.windowId, $0) }, uniquingKeysWith: { a, _ in a }))
        return true
    }

    func reset() { entries = [:] }
}
