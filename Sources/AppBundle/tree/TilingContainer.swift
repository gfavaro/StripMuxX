import AppKit
import Common

/// The strip (horizontal, a workspace's root) or one of its columns holding a
/// vertical stack of windows.
final class TilingContainer: TreeNode, NonLeafTreeNodeObject {
    let orientation: Orientation

    @MainActor
    init(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, _ orientation: Orientation, index: Int) {
        self.orientation = orientation
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }
}

extension TilingContainer {
    var isRootContainer: Bool { parent is Workspace }
}
