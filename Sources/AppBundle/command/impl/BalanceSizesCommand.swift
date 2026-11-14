import AppKit
import Common
import Foundation

/// Every column returns to the configured width, and every stack shares its height equally.
struct BalanceSizesCommand: Command {
    let args: BalanceSizesCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        for column in target.workspace.rootTilingContainer.children {
            column.scrollingColumnWidth = nil
            guard let stack = column as? TilingContainer else { continue }
            for window in stack.children { window.setWeight(stack.orientation, 1) }
        }
        return true
    }
}
