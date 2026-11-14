import AppKit
import Common

/// A dialog floats; an ordinary window joins the strip. Popups are never adopted.
@MainActor
func bindingDataForNewWindow(type: AxUiElementWindowType, workspace: Workspace, window: Window?) -> BindingData {
    switch type {
        case .popup, .dialog: BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: bindingDataForNewRegularWindow(workspace, window: window)
    }
}

@MainActor
func bindingDataForNewRegularWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    guard config.automaticallyTileNewWindows else {
        window?.unbindFromParent()
        return BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    return bindingDataForNewTilingWindow(workspace, window: window)
}

/// A new window becomes a column of its own, right of the focused column.
@MainActor
func bindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent()
    let root = workspace.rootTilingContainer
    let focused = focus.windowOrNil?.topLevelWorkspaceGroup
    let index = focused.flatMap { root.children.firstIndex(of: $0) }.map { $0 + 1 } ?? root.children.count
    return BindingData(parent: root, adaptiveWeight: WEIGHT_AUTO, index: index)
}
