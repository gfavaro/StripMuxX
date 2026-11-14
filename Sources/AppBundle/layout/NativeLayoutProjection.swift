import Foundation

extension TreeNode {
    /// Presentation-only filtering. Retained windows and stacks never leave the live
    /// tree merely because native AX cannot currently expose them.
    var hasNativeLayoutWindow: Bool {
        if let window = self as? Window { return window.nativeLayoutEligible }
        return children.contains(where: \.hasNativeLayoutWindow)
    }
}

extension TilingContainer {
    /// The children that take room: every one except those macOS currently hides.
    var frameLayoutChildren: [TreeNode] { children.filter(\.hasNativeLayoutWindow) }
}
