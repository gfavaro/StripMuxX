import AppKit
import Common

/// macOS owns desktops, so they are numbered in Control-N order, and navigation and
/// cross-Space moves run outside the tiling fence.
extension NativeWorkspaceLifecycle {
    private var state: NativeWorkspaceLifecycle { self }

    /// After a command outside the tiling fence moved focus.
    func focusDidMove(to window: Window?) {
        // Inside the fence the coordinator brings the result forward itself.
        guard !NativeTilingCommandScope.active else { return }
        window?.nativeFocus()
    }

    /// Switches to the window's desktop unless it already shows, waits for it to show and for
    /// tiling to be ready, then focuses the window directly. Never re-dispatches `focus`.
    func focusWindowOnHiddenDesktop(_ id: UInt32?, _ io: CmdIo) async throws -> Bool {
        guard let id, let window = Window.get(byId: id), let desktop = window.nodeWorkspace,
              let number = nativeDesktopNumber(of: desktop) else { return io.err("Window \(id ?? 0) is not on a desktop") }
        if !desktop.isVisible {
            guard case .cmd(let command) = parseCommand("workspace \(number)"), let switchTo = command as? WorkspaceCommand,
                  await state.navigation.selectDesktop(switchTo.args, io: io) else { return false }
        }
        _ = await state.stateChanges.wait(timeout: .seconds(2)) { desktop.isVisible && state.tiling.ready }
        try Task.checkCancellation()
        guard desktop.isVisible, window.focusWindow() else { return io.err("Desktop \(number) did not show in time; try again") }
        window.nativeFocus()
        return true
    }

    /// Brings back the window focused before, switching to its desktop first when needed.
    func focusPreviousWindow(_ io: CmdIo) async throws -> Bool {
        guard let id = state.activity.previousFocusedWindow, Window.get(byId: id) != nil else {
            return io.err("Prev window has been closed")
        }
        if let error = try await focusNativeWindow(id) { return io.err(error) }
        return true
    }

    /// `enable`: disabling stops tiling and shortcuts and puts windows back where they
    /// were; enabling resumes with a fresh observation.
    func setEnabled(_ args: EnableCmdArgs, _ io: CmdIo) async throws -> Bool {
        let model = TrayMenuModel.shared
        let newState: Bool = switch args.targetState.val {
            case .on: true
            case .off: false
            case .toggle: !model.isEnabled
        }
        if newState == model.isEnabled {
            if !args.failIfNoop {
                io.out((newState ? "Already enabled" : "Already disabled") + "Tip: use --fail-if-noop to exit with non-zero code")
            }
            return !args.failIfNoop
        }
        // Turning off keeps tiling's grants until the restore has taken its leases.
        if newState { model.isEnabled = true; state.setTopUpEnabled(true) }
        if newState {
            try await activateMode(mainModeId)
            state.observation?.requestRead(event: "enabled")
        } else {
            state.setTopUpEnabled(false)
            MacApp.cancelPendingFocus()
            await stopNativeTilingAndRestoreFrames()
            try await activateMode(nil)
        }
        updateTrayText()
        return true
    }

    /// A window's geometry changed: one its app moved by itself is put back on its tile.
    func windowGeometryChanged(_ windowId: UInt32?) {
        guard let windowId, let window = Window.get(byId: windowId) else { return }
        window.invalidateLastKnownNativeState()
        if NSEvent.pressedMouseButtons == 0 { NativeFrameRecovery.shared.windowChanged(window) }
    }
}

/// Stops tiling before the writes, so no layout moves a window back while it is being restored.
@MainActor
func stopNativeTilingAndRestoreFrames() async {
    await NativeOriginalFrames.shared.restore {
        TrayMenuModel.shared.isEnabled = false
        runtime.native.tiling.invalidate("disabled")
    }
}
