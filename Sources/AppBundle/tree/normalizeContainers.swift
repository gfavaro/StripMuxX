extension Workspace {
    /// Keeps the tree in strip shape: the root's children are columns, and a column is a
    /// window or a vertical stack of at least two windows.
    @MainActor func normalizeContainers() {
        let root = rootTilingContainer
        for column in root.children {
            guard let stack = column as? TilingContainer else { continue }
            // A stack never nests: windows of a deeper container join the stack itself.
            for nested in stack.children.filterIsInstance(of: TilingContainer.self) {
                let binding = nested.unbindFromParent()
                for (offset, window) in nested.allLeafWindowsRecursive.enumerated() {
                    window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: binding.index + offset)
                }
            }
            switch stack.children.count {
                case 0:
                    if scrollingPinnedNode === stack { scrollingPinnedNode = nil }
                    stack.unbindFromParent()
                case 1:
                    let window = stack.children[0]
                    let mru = root.mostRecentChild
                    let binding = stack.unbindFromParent()
                    window.scrollingColumnWidth = stack.scrollingColumnWidth
                    window.bind(to: root, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                    if scrollingPinnedNode === stack { scrollingPinnedNode = window }
                    (mru === stack ? window : mru)?.markAsMostRecentChild()
                default: break
            }
        }
    }
}
