import Common

struct CmdEnv: ConvenienceCopyable {
    var extraEnvironment: [String: String] = [:]
    var windowId: UInt32?
    var workspaceName: String?

    static let defaultEnv: CmdEnv = .init()
    func withFocus(_ focus: LiveFocus) -> CmdEnv {
        if let window = focus.windowOrNil {
            CmdEnv(extraEnvironment: extraEnvironment, windowId: window.windowId)
        } else {
            CmdEnv(extraEnvironment: extraEnvironment, workspaceName: focus.workspace.name)
        }
    }

    var asMap: [String: String] {
        var result = extraEnvironment
        if let windowId {
            result[WINMUX_WINDOW_ID] = windowId.description
        }
        if let workspaceName {
            result[WINMUX_WORKSPACE] = workspaceName.description
        }
        return result
    }
}

/// What hooks see about the moment they run in.
@MainActor func hookEnvironment(event: String, previousMode: String? = nil) -> CmdEnv {
    let mode = activeMode.flatMap { name in config.modes[name].map { ModePresentation(name: name, mode: $0) } }
    return CmdEnv(extraEnvironment: [
        "WINMUX_EVENT": event, "WINMUX_MODE": activeMode ?? "", "WINMUX_PREV_MODE": previousMode ?? "",
        "WINMUX_MODE_INITIAL": mode?.initial ?? "", "WINMUX_MODE_COLOR": mode.map { stateColorHex(menuBarModeColor($0)) } ?? "",
        "WINMUX_WORKSPACE": userFacingWorkspaceName(focus.workspace), "WINMUX_WINDOW_ID": focus.windowOrNil.map { String($0.windowId) } ?? "",
        "WINMUX_MONITOR_UUID": focus.workspace.workspaceMonitor.displayUUID ?? "",
        "WINMUX_ENABLED": String(TrayMenuModel.shared.isEnabled), "WINMUX_SUSPENDED": String(runtime.hotkeys.hotkeysSuspended),
    ])
}
