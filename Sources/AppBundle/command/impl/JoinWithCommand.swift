import AppKit
import Common

/// Puts the focused window into the column on that side, stacked with its windows.
struct JoinWithCommand: Command {
    let args: JoinWithCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard window.parent is TilingContainer else {
            return io.err("join-with does not support non-tiling windows")
        }
        guard direction.orientation == .h else {
            return io.err("join-with takes left or right: a window joins the column beside it")
        }
        let columns = target.workspace.workspaceLayoutUnits
        guard let index = columns.firstIndex(where: { $0 === window.topLevelWorkspaceGroup }),
              let neighbor = columns.getOrNil(atIndex: index + direction.focusOffset) else {
            io.out("join-with: nothing to do")
            return true
        }
        // Joining to the right puts the window on top, as it reads left to right, top to bottom.
        stack(window, with: neighbor, above: direction.isPositive, in: target.workspace)
        scheduleRefreshSession(.globalObserver("joinScrolling"))
        return true
    }
}
