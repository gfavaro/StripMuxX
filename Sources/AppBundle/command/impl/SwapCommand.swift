import AppKit
import Common

struct SwapCommand: Command {
    let args: SwapCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else {
            return false
        }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard currentWindow.parent is TilingContainer else { return io.err("swap does not support floating windows") }

        let targetWindow: Window?
        switch args.target.val {
            case .direction(let direction):
                let column = currentWindow.topLevelWorkspaceGroup
                // Up and down stay within the stack; left and right reach the next column's window.
                let siblings = direction.orientation == .v
                    ? (column as? TilingContainer)?.frameLayoutChildren ?? [currentWindow]
                    : target.workspace.workspaceLayoutUnits
                let own: TreeNode = direction.orientation == .v ? currentWindow : column
                guard let index = siblings.firstIndex(where: { $0 === own }) else { return false }
                var targetIndex = index + direction.focusOffset
                if !siblings.indices.contains(targetIndex) {
                    guard args.wrapAround else { return false }
                    targetIndex = (targetIndex + siblings.count) % siblings.count
                }
                targetWindow = siblings[targetIndex].mostRecentWindowRecursive
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return false
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    if !args.wrapAround {
                        return false
                    }
                    targetIndex = (targetIndex + windows.count) % windows.count
                }
                targetWindow = windows[targetIndex]
        }

        guard let targetWindow, targetWindow !== currentWindow else {
            return false
        }

        swapNodes(currentWindow, targetWindow)

        if args.swapFocus {
            return targetWindow.focusWindow()
        }
        return true
    }
}
