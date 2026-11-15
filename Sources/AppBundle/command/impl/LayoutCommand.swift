import AppKit
import Common

/// Floats a window or returns it to the strip.
struct LayoutCommand: Command {
    let args: LayoutCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        if args.forNextDetectedWindow {
            layoutForNextDetectedWindow = args.toggleBetween.val.first
            return true
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let current: LayoutCmdArgs.LayoutDescription = window.isFloating ? .floating : (window.freeSizeRect == nil ? .tiling : .freeSize)
        let wanted = nextLayout(in: args.toggleBetween.val, matching: { $0 == current })
        if wanted == current { return false }
        switch wanted {
            case .tiling:
                if window.freeSizeRect != nil {
                    let group = window.topLevelWorkspaceGroup
                    group.scrollingColumnWidth = window.freeSizePreviousColumnWidth
                    group.scrollingColumnFixedWidth = window.freeSizePreviousFixedWidth
                    window.freeSizeRect = nil
                    window.freeSizePreviousColumnWidth = nil
                    window.freeSizePreviousFixedWidth = nil
                    return true
                }
                let registration = runtime.native.layouts.registration(for: window.windowId)
                let size = try await window.getAxSize()
                guard let registration, runtime.native.layouts.accepts(registration) else {
                    return io.err("The window's desktop changed while reading its size")
                }
                window.lastFloatingSize = size ?? window.lastFloatingSize
                let data = bindingDataForNewTilingWindow(target.workspace, window: window)
                window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
            case .freeSize:
                let registration = runtime.native.layouts.registration(for: window.windowId)
                let observedRect = try await window.getAxRect()
                guard let registration, runtime.native.layouts.accepts(registration),
                      let rect = observedRect, rect.width > 0, rect.height > 0 else {
                    return io.err("Could not read a stable native window frame")
                }
                if window.isFloating {
                    let data = bindingDataForNewTilingWindow(target.workspace, window: window)
                    window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
                }
                let group = window.topLevelWorkspaceGroup
                window.freeSizePreviousColumnWidth = group.scrollingColumnWidth
                window.freeSizePreviousFixedWidth = group.scrollingColumnFixedWidth
                window.freeSizeRect = rect
                group.scrollingColumnFixedWidth = rect.width
            case .floating:
                if window.freeSizeRect != nil {
                    window.freeSizeRect = nil
                    window.freeSizePreviousColumnWidth = nil
                    window.freeSizePreviousFixedWidth = nil
                }
                window.bindAsFloatingWindow(to: target.workspace)
                target.workspace.normalizeContainers()
                if let size = window.lastFloatingSize { window.setAxFrame(nil, size) }
        }
        return true
    }
}

@MainActor var layoutForNextDetectedWindow: LayoutCmdArgs.LayoutDescription?

/// `layout --for-next-detected-window`: the next window adopted floats, or joins the strip.
@MainActor
func applyLayoutForNextDetectedWindow(_ window: Window, on workspace: Workspace) {
    guard let layout = layoutForNextDetectedWindow else { return }
    layoutForNextDetectedWindow = nil
    switch layout {
        case .floating: window.bindAsFloatingWindow(to: workspace)
        case .freeSize:
            guard window.isFloating else { return }
            let data = bindingDataForNewTilingWindow(workspace, window: window)
            window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
            if let rect = window.lastKnownActualRect, rect.width > 0, rect.height > 0 {
                let group = window.topLevelWorkspaceGroup
                window.freeSizePreviousColumnWidth = group.scrollingColumnWidth
                window.freeSizePreviousFixedWidth = group.scrollingColumnFixedWidth
                window.freeSizeRect = rect
                group.scrollingColumnFixedWidth = rect.width
            }
        case .tiling:
            guard window.isFloating else { return }
            let data = bindingDataForNewTilingWindow(workspace, window: window)
            window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}
