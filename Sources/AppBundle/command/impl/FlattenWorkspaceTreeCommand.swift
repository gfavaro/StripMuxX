import AppKit
import Common

/// Dissolves every stack: each window becomes a column of its own, in order.
struct FlattenWorkspaceTreeCommand: Command {
    let args: FlattenWorkspaceTreeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        let focusedWindow = focus.windowOrNil
        for window in workspace.rootTilingContainer.allLeafWindowsRecursive {
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        workspace.normalizeContainers()
        if let focusedWindow { focusedWindow.markAsMostRecentChild() }
        return true
    }
}
