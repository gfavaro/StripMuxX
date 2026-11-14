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
        let current: LayoutCmdArgs.LayoutDescription = window.isFloating ? .floating : .tiling
        let wanted = nextLayout(in: args.toggleBetween.val, matching: { $0 == current })
        if wanted == current { return false }
        switch wanted {
            case .tiling:
                let registration = runtime.native.layouts.registration(for: window.windowId)
                let size = try await window.getAxSize()
                guard let registration, runtime.native.layouts.accepts(registration) else {
                    return io.err("The window's desktop changed while reading its size")
                }
                window.lastFloatingSize = size ?? window.lastFloatingSize
                let data = bindingDataForNewTilingWindow(target.workspace, window: window)
                window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
            case .floating:
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
        case .tiling:
            guard window.isFloating else { return }
            let data = bindingDataForNewTilingWindow(workspace, window: window)
            window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}
