import Common

enum TreeNodeCases {
    case window(Window)
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
}

enum NonLeafTreeNodeCases {
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
}

protocol NonLeafTreeNodeObject: TreeNode {}

extension TreeNode {
    var nodeCases: TreeNodeCases {
        if let window = self as? Window {
            return .window(window)
        } else if let workspace = self as? Workspace {
            return .workspace(workspace)
        } else if let tilingContainer = self as? TilingContainer {
            return .tilingContainer(tilingContainer)
        } else {
            die("Unknown tree")
        }
    }
}

extension NonLeafTreeNodeObject {
    var cases: NonLeafTreeNodeCases {
        if let workspace = self as? Workspace {
            return .workspace(workspace)
        } else if let tilingContainer = self as? TilingContainer {
            return .tilingContainer(tilingContainer)
        } else {
            die("Unknown tree \(self)")
        }
    }
}

enum ChildParentRelation: Equatable {
    case floatingWindow
    /// A column of the strip, or a window of a stack.
    case tiling(parent: TilingContainer)
    case rootTilingContainer
}

func getChildParentRelation(child: TreeNode, parent: NonLeafTreeNodeObject) -> ChildParentRelation {
    if let relation = getChildParentRelationOrNil(child: child, parent: parent) {
        return relation
    }
    illegalChildParentRelation(child: child, parent: parent)
}

func illegalChildParentRelation(child: TreeNode, parent: NonLeafTreeNodeObject?) -> Never {
    die("Illegal child-parent relation. Child: \(child), Parent: \((parent ?? child.parent).prettyDescription)")
}

func getChildParentRelationOrNil(child: TreeNode, parent: NonLeafTreeNodeObject) -> ChildParentRelation? {
    return switch (child.nodeCases, parent.cases) {
        case (.workspace, _): nil
        case (.window, .workspace): .floatingWindow
        case (.tilingContainer, .tilingContainer(let container)),
             (.window, .tilingContainer(let container)): .tiling(parent: container)
        case (.tilingContainer, .workspace): .rootTilingContainer
    }
}
