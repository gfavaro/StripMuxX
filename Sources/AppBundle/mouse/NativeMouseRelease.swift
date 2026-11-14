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
          let drop = workspace.allLeafWindowsRecursive.first(where: {
              $0 !== window && $0.parent is TilingContainer && $0.nativeLayoutEligible &&
                  $0.lastAppliedLayoutPhysicalRect?.contains(pointer) == true
          }) else { return .none }
    swapNodes(window, drop)
    return .swapped(with: drop.windowId)
}
