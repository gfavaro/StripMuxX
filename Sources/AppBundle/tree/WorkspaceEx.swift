import Common

extension Workspace {
    private func existingContainer<T: TreeNode>(_ type: T.Type) -> T? {
        let containers = children.filterIsInstance(of: T.self)
        return switch containers.count {
            case 0: nil
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one \(T.self)")
        }
    }

    /// The strip: its children are the columns, left to right.
    @MainActor var rootTilingContainer: TilingContainer {
        existingContainer(TilingContainer.self)
            ?? TilingContainer(parent: self, adaptiveWeight: 1, .h, index: INDEX_BIND_LAST)
    }

    var floatingWindows: [Window] {
        children.filterIsInstance(of: Window.self)
    }

}

extension Workspace {
    /// The columns shown: windows macOS currently hides (minimized, another app's
    /// fullscreen) keep their place in the tree but take no room on the strip.
    @MainActor
    var workspaceLayoutUnits: [TreeNode] {
        rootTilingContainer.children.filter(\.hasNativeLayoutWindow)
    }
}

extension TreeNode {
    /// The column this node belongs to: itself, or the stack that holds it.
    @MainActor
    var topLevelWorkspaceGroup: TreeNode {
        var node: TreeNode = self
        while let parent = node.parent as? TilingContainer, !(parent.parent is Workspace) {
            node = parent
        }
        return node
    }
}
