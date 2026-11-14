import AppKit
import Common

/// Left and right move a column along the strip, or take a window out of its stack
/// into a column of its own. Up and down reorder a stack.
struct MoveCommand: Command {
    let args: MoveCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard window.parent is TilingContainer else {
            return io.err("moving floating windows isn't supported")
        }
        let workspace = target.workspace
        let column = window.topLevelWorkspaceGroup
        if direction.orientation == .v {
            guard let stack = window.parent as? TilingContainer, stack === column, let index = window.ownIndex,
                  let sibling = stack.children.getOrNil(atIndex: index + direction.focusOffset) else { return false }
            swapNodes(window, sibling)
            scheduleRefreshSession(.globalObserver("moveWithinScrollingColumn"))
            return true
        }
        let root = workspace.rootTilingContainer
        if column !== window {
            // Out of its stack, into a column beside it.
            let width = column.scrollingColumnWidth
            guard let at = column.ownIndex else { return false }
            window.unbindFromParent()
            window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: at + (direction.isPositive ? 1 : 0))
            window.scrollingColumnWidth = width
            workspace.normalizeContainers()
            scheduleRefreshSession(.globalObserver("moveScrollingColumn"))
            return true
        }
        // Columns macOS currently hides take no place on the strip, so the neighbour is
        // the next shown column, and the index comes from the tree.
        let shown = workspace.workspaceLayoutUnits
        guard let index = shown.firstIndex(where: { $0 === column }) else { return false }
        guard let neighbor = shown.getOrNil(atIndex: index + direction.focusOffset) else {
            return hitStripEnd(window, io, direction)
        }
        let binding = column.unbindFromParent()
        guard let neighborIndex = neighbor.ownIndex else {
            column.bind(to: root, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
            return false
        }
        column.bind(to: root, adaptiveWeight: binding.adaptiveWeight, index: neighborIndex + (direction.isPositive ? 1 : 0))
        scheduleRefreshSession(.globalObserver("moveScrollingColumn"))
        return true
    }

    /// Past the strip's end, `--boundaries all-monitors-outer-frame` continues onto the
    /// display on that side: the window leaves this desktop once the command ends.
    @MainActor
    private func hitStripEnd(_ window: Window, _ io: CmdIo, _ direction: CardinalDirection) -> Bool {
        if args.boundaries == .allMonitorsOuterFrame,
           let (monitors, index) = window.nodeMonitor?.findRelativeMonitor(inDirection: direction), monitors.indices.contains(index) {
            guard let sink = NativeTilingCommandScope.monitorMoveSink else {
                return io.err("Moving to another display runs through the tiling fence")
            }
            sink.pending = MoveNodeToMonitorCmdArgs(target: .direction(direction))
                .copy(\.windowId, window.windowId)
                .copy(\.focusFollowsWindow, focus.windowOrNil == window)
            return true
        }
        return args.boundariesAction != .fail
    }
}
