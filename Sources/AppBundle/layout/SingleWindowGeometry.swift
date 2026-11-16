import AppKit
import Common

/// A fullscreen window fills the display's available area.
@MainActor
func fullscreenWindowRect(_ window: Window, in workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    return window.noOuterGapsInFullscreen ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
}

/// A lone window is at most `ratio` times as wide as it is tall, so it keeps one shape on any
/// display; 0 lets it fill the width. A window's own minimum width always wins.
func singleWindowLimitedRect(available: Rect, ratio: Double, minimumWidth: CGFloat,
                             alignment: SingleWindowAlignment = .center) -> Rect {
    guard ratio.isFinite, ratio > 0 else { return available }
    let width = min(available.width, max(max(available.height - 1, 0) * CGFloat(ratio), minimumWidth))
    return alignedSingleWindowRect(available: available, width: width, minimumWidth: minimumWidth, alignment: alignment)
}

@MainActor
func singleWindowWidthTarget(in workspace: Workspace) -> Window? {
    let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
    guard windows.count == 1, let window = windows.first, !window.isFullscreen else { return nil }
    return window
}

@MainActor
func workspaceTilingRect(_ workspace: Workspace) -> Rect {
    let available = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    guard let window = singleWindowWidthTarget(in: workspace) else { return available }
    let settings = workspace.windowWidthSettings
    let alignment = settings.singleWindowAlignment ?? .center
    if let width = window.singleWindowManualWidth {
        return alignedSingleWindowRect(available: available, width: width, minimumWidth: window.minimumLayoutSize.width, alignment: alignment)
    }
    return singleWindowLimitedRect(available: available, ratio: settings.aspectRatio ?? defaultSingleWindowAspectRatio,
                                   minimumWidth: window.minimumLayoutSize.width, alignment: alignment)
}

func alignedSingleWindowRect(available: Rect, width: CGFloat, minimumWidth: CGFloat, alignment: SingleWindowAlignment = .center) -> Rect {
    guard width.isFinite, width > 0 else { return available }
    let fittedWidth = min(available.width, max(width, minimumWidth))
    let inset: CGFloat = switch alignment {
        case .left: 0
        case .center: (available.width - fittedWidth) / 2
        case .right: available.width - fittedWidth
    }
    return Rect(topLeftX: available.topLeftX + inset,
        topLeftY: available.topLeftY, width: fittedWidth, height: available.height)
}

@MainActor
@discardableResult
func applySingleWindowManualResize(_ window: Window, width: CGFloat) -> Bool {
    guard width.isFinite, width > 0, let workspace = window.nodeWorkspace,
          singleWindowWidthTarget(in: workspace) === window else { return false }
    window.singleWindowManualWidth = width
    return true
}
