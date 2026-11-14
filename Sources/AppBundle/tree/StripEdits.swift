import AppKit
import Common

// Edits of a strip's tree shared by commands and the mouse.

@MainActor
func swapNodes(_ node1: TreeNode, _ node2: TreeNode) {
    if node1 == node2 { return }
    guard let index1 = node1.ownIndex else { return }
    guard let index2 = node2.ownIndex else { return }

    if index1 < index2 {
        let binding2 = node2.unbindFromParent()
        let binding1 = node1.unbindFromParent()

        node2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
        node1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
    } else {
        let binding1 = node1.unbindFromParent()
        let binding2 = node2.unbindFromParent()

        node1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
        node2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    }
    node1.markAsMostRecentChild()
}

/// Sets the width, in points, of the column holding `window`, within what its windows
/// and the viewport allow. Returns the width applied, or nil when the window has no
/// column on the strip (it floats, or its column is pinned).
@MainActor
@discardableResult
func resizeColumn(of window: Window, toWidth requested: CGFloat, in workspace: Workspace) -> CGFloat? {
    let metrics = workspace.scrollingMetrics
    let group = window.topLevelWorkspaceGroup
    guard let column = metrics.columns.first(where: { $0.node === group }) else { return nil }
    let lower = group.minimumLayoutExtent(along: .h)
    let maximum = max(metrics.areaWidth - column.frameStartInset - column.frameEndInset, lower)
    let actual = min(max(requested, lower), maximum)
    if abs(actual - column.width) >= 0.5 {
        group.scrollingColumnFixedWidth = nil
        group.scrollingColumnWidth = min(max((actual + column.frameStartInset + column.frameEndInset) / max(metrics.areaWidth, 1), 0.1), 1)
    }
    return actual
}

/// Changes a stacked window's height by `delta` points, taking the difference from
/// the other windows of its stack equally. Returns the change applied, or nil when the
/// window is not in a stack.
@MainActor
@discardableResult
func resizeInStack(_ window: Window, by delta: CGFloat) -> CGFloat? {
    guard let stack = window.parent as? TilingContainer, !stack.isRootContainer else { return nil }
    let siblings = stack.children.filter { $0 !== window }
    guard !siblings.isEmpty else { return nil }
    let axis = stack.orientation
    let multiplier = -1 / CGFloat(siblings.count)
    let diff = constrainedTiledResizeDiff(delta, adjustments:
        [TiledResizeAdjustment(weight: window.getWeight(axis), multiplier: 1)] +
            siblings.map { TiledResizeAdjustment(weight: $0.getWeight(axis), multiplier: multiplier) })
    for sibling in siblings { sibling.setWeight(axis, sibling.getWeight(axis) + diff * multiplier) }
    window.setWeight(axis, window.getWeight(axis) + diff)
    return diff
}

@MainActor
@discardableResult
func resizeInStack(_ window: Window, toHeight height: CGFloat) -> Bool {
    guard let current = window.lastAppliedLayoutVirtualRect?.height ?? window.lastAppliedLayoutPhysicalRect?.height,
          let applied = resizeInStack(window, by: height - current) else { return false }
    return abs(applied) >= 0.5
}

/// Puts `window` and `target` in one column, `window` above when `above`. The stack
/// takes the place and width of `target`'s column.
@MainActor
func stack(_ window: Window, with target: TreeNode, above: Bool, in workspace: Workspace) {
    guard window !== target, window.parent is TilingContainer else { return }
    window.unbindFromParent()
    if let stack = target as? TilingContainer {
        window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: above ? 0 : INDEX_BIND_LAST)
    } else if let stack = target.parent as? TilingContainer, !stack.isRootContainer, let index = target.ownIndex {
        window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: above ? index : index + 1)
    } else {
        let binding = target.unbindFromParent()
        let stack = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, .v, index: binding.index)
        stack.scrollingColumnWidth = target.scrollingColumnWidth
        stack.scrollingColumnFixedWidth = target.scrollingColumnFixedWidth
        target.scrollingColumnWidth = nil
        target.scrollingColumnFixedWidth = nil
        target.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: 0)
        window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: above ? 0 : INDEX_BIND_LAST)
    }
    window.scrollingColumnWidth = nil
    window.scrollingColumnFixedWidth = nil
    workspace.normalizeContainers()
}
