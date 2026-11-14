import AppKit
import Common

/// Width resizes the focused column; height resizes a window within its stack.
struct ResizeCommand: Command {
    let args: ResizeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        guard window.parent is TilingContainer else {
            return io.err("resize command doesn't support floating windows")
        }
        let workspace = target.workspace
        func requested(from current: CGFloat) -> CGFloat {
            switch args.units.val {
                case .set(let value): CGFloat(value)
                case .add(let value): current + CGFloat(value)
                case .subtract(let value): current - CGFloat(value)
            }
        }
        switch args.dimension.val {
            case .width, .smart:
                if singleWindowWidthTarget(in: workspace) === window {
                    let width = requested(from: workspaceTilingRect(workspace).width)
                    return applySingleWindowManualResize(window, width: max(minimumTiledResizeWeight, width))
                }
                guard let column = workspace.scrollingMetrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) else {
                    return io.err("The focused window has no column on the strip")
                }
                let width = requested(from: column.width)
                guard let applied = resizeColumn(of: window, toWidth: width, in: workspace) else { return false }
                if width + 1 < applied { noteMinimum(of: column.node, dimension: "width") }
                if abs(applied - column.width) < 0.5 { io.out("resize: nothing to do"); return true }
                scheduleRefreshSession(.globalObserver("resizeScrollingColumn"))
                return true
            case .height, .smartOpposite:
                let current = window.getWeight(.v)
                let delta = requested(from: current) - current
                guard let applied = resizeInStack(window, by: delta) else { io.out("resize: nothing to do"); return true }
                if abs(applied - delta) > 0.01, let stack = window.parent as? TilingContainer { noteMinimum(of: stack, dimension: "height") }
                return true
        }
    }
}

/// Says which app's minimum size stopped a resize.
@MainActor
private func noteMinimum(of node: TreeNode, dimension: String) {
    guard let blocked = node.allLeafWindowsRecursive.compactMap({ $0 as? MacWindow }).first(where: {
        dimension == "width" ? $0.minimumLayoutSize.width > 0 : $0.minimumLayoutSize.height > 0
    }) else { return }
    NoticePanel.shared.showMinimumSize(appName: blocked.macApp.name ?? blocked.macApp.rawAppBundleId ?? "Application",
                                       dimension: dimension, minimum: blocked.minimumLayoutSize)
}
