import AppKit
import Common

enum NativeMouseReleaseOutcome: Equatable {
    case none, resized, swapped(with: UInt32)
}

/// There is no live drag driver; the layout pauses while a button is down. On release,
/// a tiled window the user resized keeps its new size (its column's width, its share of
/// a stack's height), and one dropped onto another tile on its desktop swaps with it.
/// Anything else snaps back on the next layout.
@MainActor
func adoptNativeMouseRelease(_ window: Window, actual: Rect, pointer: CGPoint) -> NativeMouseReleaseOutcome {
    guard window.parent is TilingContainer, let workspace = window.nodeWorkspace, workspace.isVisible,
          let target = window.lastAppliedLayoutPhysicalRect else { return .none }
    if let preferred = window.freeSizeRect {
        // The user owns both dimensions and the vertical position of a free-size
        // strip column. A native resize updates its preference instead of being
        // interpreted as a tiled resize or a drag/swap.
        if abs(actual.width - target.width) > 5 || abs(actual.height - target.height) > 5 ||
           abs(actual.topLeftY - preferred.topLeftY) > 5 {
            guard actual.width > 0, actual.height > 0 else { return .none }
            window.freeSizeRect = actual
            window.topLevelWorkspaceGroup.scrollingColumnFixedWidth = actual.width
            return .resized
        }
        return .none
    }
    if abs(actual.width - target.width) > 5 || abs(actual.height - target.height) > 5 {
        var resized = false
        if abs(actual.width - target.width) > 5 {
            resized = applySingleWindowManualResize(window, width: actual.width) ||
                resizeColumn(of: window, toWidth: actual.width, in: workspace) != nil
        }
        if abs(actual.height - target.height) > 5, resizeInStack(window, toHeight: actual.height) { resized = true }
        return resized ? .resized : .none
    }
    guard hypot(actual.center.x - target.center.x, actual.center.y - target.center.y) > 30,
          let drop = nativeMouseSwapTarget(for: window, at: pointer) else { return .none }
    swapNodes(window, drop)
    return .swapped(with: drop.windowId)
}

/// Shared target selection for the non-interactive drag preview and real drop.
/// Only uses already accepted layout geometry; does not query Accessibility.
@MainActor
func nativeMouseSwapTarget(for dragged: Window, at pointer: CGPoint) -> Window? {
    guard let workspace = dragged.nodeWorkspace, workspace.isVisible,
          dragged.parent is TilingContainer else { return nil }
    return workspace.allLeafWindowsRecursive.first {
        $0 !== dragged && $0.parent is TilingContainer && $0.nativeLayoutEligible &&
        $0.lastAppliedLayoutPhysicalRect?.contains(pointer) == true
    }
}
