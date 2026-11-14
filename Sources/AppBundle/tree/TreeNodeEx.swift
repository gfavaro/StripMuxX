import AppKit
import Common

extension TreeNode {
    private func visit(node: TreeNode, result: inout [Window]) {
        if let node = node as? Window {
            result.append(node)
        }
        for child in node.children {
            visit(node: child, result: &result)
        }
    }
    var allLeafWindowsRecursive: [Window] {
        var result: [Window] = []
        visit(node: self, result: &result)
        return result
    }

    func containsLeafWindow(withId windowId: UInt32) -> Bool {
        if let window = self as? Window {
            return window.windowId == windowId
        }
        return children.contains { $0.containsLeafWindow(withId: windowId) }
    }

    var ownIndex: Int? {
        guard let parent else { return nil }
        return parent.children.firstIndex(of: self).orDie()
    }

    var parents: [NonLeafTreeNodeObject] { parent.flatMap { [$0] + $0.parents } ?? [] }
    var parentsWithSelf: [TreeNode] { parent.flatMap { [self] + $0.parentsWithSelf } ?? [self] }

    var nodeWorkspace: Workspace? {
        self as? Workspace ?? parent?.nodeWorkspace
    }

    @MainActor
    var nodeMonitor: Monitor? { nodeWorkspace?.workspaceMonitor }

    var mostRecentWindowRecursive: Window? {
        self as? Window ?? mostRecentChild?.mostRecentWindowRecursive
    }

    var mostRecentWorkspaceFocusableWindowRecursive: Window? {
        mostRecentWorkspaceFocusableWindowRecursive(excluding: nil)
    }

    func mostRecentWorkspaceFocusableWindowRecursive(excluding excludedWindow: Window?) -> Window? {
        switch nodeCases {
            case .window(let window):
                return window != excludedWindow && window.participatesInWorkspaceFocus ? window : nil
            case .tilingContainer, .workspace:
                return childrenByMostRecentUse.lazy.compactMap { $0.mostRecentWorkspaceFocusableWindowRecursive(excluding: excludedWindow) }.first
        }
    }

    var anyLeafWindowRecursive: Window? {
        if let window = self as? Window {
            return window
        }
        for child in children {
            if let window = child.anyLeafWindowRecursive {
                return window
            }
        }
        return nil
    }

    // Doesn't contain at least one window
    var isEffectivelyEmpty: Bool {
        anyLeafWindowRecursive == nil
    }

    @MainActor
    var hWeight: CGFloat {
        get { getWeight(.h) }
        set { setWeight(.h, newValue) }
    }

    @MainActor
    var vWeight: CGFloat {
        get { getWeight(.v) }
        set { setWeight(.v, newValue) }
    }

}

extension Window {
    var participatesInWorkspaceFocus: Bool {
        nativeLayoutEligible && parent != nil
    }
}
