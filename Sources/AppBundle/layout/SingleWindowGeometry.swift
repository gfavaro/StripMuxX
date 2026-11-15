import AppKit
import Common

func windowWidthRect(available: Rect, fraction: Double, minimumWidth: CGFloat,
                     alignment: SingleWindowAlignment = .center) -> Rect {
    alignedSingleWindowRect(available: available, width: available.width * fraction,
                            minimumWidth: minimumWidth, alignment: alignment)
}

@MainActor
func fullscreenWindowRect(_ window: Window, in workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    let available = window.noOuterGapsInFullscreen ? monitor.visibleRect : monitor.visibleRectPaddedByOuterGaps
    guard let fraction = workspace.windowWidthSettings.fullscreenWidth else { return available }
    return windowWidthRect(available: available, fraction: fraction, minimumWidth: window.minimumLayoutSize.width)
}

func singleWindowLimitedRect(available: Rect, screen: Rect, ratio: Double, minimumWidth: CGFloat, alignment: SingleWindowAlignment = .center) -> Rect {
    guard ratio.isFinite, ratio > 0, screen.height > 0, screen.width / screen.height >= 2.3 else { return available }
    let width = min(available.width, max(max(available.height - 1, 0) * CGFloat(ratio), minimumWidth))
    return alignedSingleWindowRect(available: available, width: width, minimumWidth: minimumWidth, alignment: alignment)
}

@MainActor
func singleWindowWidthTarget(in workspace: Workspace) -> Window? {
    let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
    guard windows.count == 1, let window = windows.first, !window.isFullscreen else { return nil }
    if workspace.windowWidthSettings.loneWindowWidth != nil ||
        workspace.windowWidthSettings.fullscreenWidth != nil { return window }
    // Compatibility for configs written before fullscreen-width.
    let monitor = workspace.workspaceMonitor
    let ratio = config.singleWindowAspectRatio.getValue(for: monitor)
    guard ratio.isFinite, ratio > 0, monitor.rect.height > 0,
          monitor.rect.width / monitor.rect.height >= 2.3 else { return nil }
    return window
}

@MainActor
func workspaceTilingRect(_ workspace: Workspace) -> Rect {
    let monitor = workspace.workspaceMonitor
    let available = monitor.visibleRectPaddedByOuterGaps
    let settings = workspace.windowWidthSettings
    if let fraction = settings.fullscreenWidth {
        if let window = workspace.rootTilingContainer.mostRecentWindowRecursive, window.isFullscreen {
            return fullscreenWindowRect(window, in: workspace)
        }
    }
    guard let window = singleWindowWidthTarget(in: workspace) else { return available }
    let alignment = settings.singleWindowAlignment ?? .center
    if let width = window.singleWindowManualWidth {
        return alignedSingleWindowRect(available: available, width: width, minimumWidth: window.minimumLayoutSize.width, alignment: alignment)
    }
    if let fraction = settings.loneWindowWidth ?? settings.fullscreenWidth {
        return windowWidthRect(available: available, fraction: fraction,
                               minimumWidth: window.minimumLayoutSize.width, alignment: alignment)
    }
    return singleWindowLimitedRect(available: available, screen: monitor.rect,
        ratio: config.singleWindowAspectRatio.getValue(for: monitor), minimumWidth: window.minimumLayoutSize.width, alignment: alignment)
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
