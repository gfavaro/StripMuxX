/// Which commands run, and which of them run outside the tiling fence: queries and
/// Space-level operations do not wait for a showing desktop's layout to be ready.
@MainActor
enum NativeCommandPolicy {
    static func accepts(_ command: any Command) -> Bool {
        isNativeDiagnosticOrQuery(command) || isNativeNavigation(command) || NativeTilingCoordinator.supports(command)
    }

    /// A sequence runs either wholly outside the tiling fence or wholly inside it. Inside,
    /// it may also switch modes (`['focus left', 'mode main']`), reload or report.
    static func acceptsSequence(_ commands: [any Command]) -> Bool {
        commands.allSatisfy(runsOutsideNativeTilingFence) || commands.allSatisfy {
            !runsOutsideNativeTilingFence($0) || $0 is DoctorCommand || $0 is ReloadConfigCommand || $0 is ModeCommand
        }
    }

    static func runsOutsideNativeTilingFence(_ command: any Command) -> Bool {
        isNativeNavigation(command) || isNativeDiagnosticOrQuery(command)
    }

    /// Read-only commands that answer from config or native snapshots,
    /// and pointer moves.
    static func isNativeDiagnosticOrQuery(_ command: any Command) -> Bool {
        switch command {
            case is DoctorCommand, is DebugWindowsCommand, is ReloadConfigCommand, is ListWorkspacesCommand, is ListWindowsCommand,
                 is ListAppsCommand, is ListModesCommand, is ListExecEnvVarsCommand, is ConfigCommand,
                 is ListMonitorsCommand, is MoveMouseCommand,
                 // Starts a process; no window or Space is touched.
                 is ExecAndForgetCommand,
                 // Switches key bindings only; it must work while tiling is paused.
                 is ModeCommand,
                 // Runs a binding's commands, which enter the fence themselves.
                 is TriggerBindingCommand: true
            // Only remembers the layout for the next window; no window is touched.
            case let command as LayoutCommand: command.args.forNextDetectedWindow
            default: false
        }
    }

    /// Space navigation and cross-Space window moves: Space-level operations that run
    /// without native tiling, outside its command fence.
    static func isNativeNavigation(_ command: any Command) -> Bool {
        switch command {
            case let command as WorkspaceCommand: NativeSpaceNavigator.supports(command.args)
            case let command as MoveNodeToWorkspaceCommand: NativeWindowSpaceMoves.supports(command.args)
            // Focus may leave the desktop toward another display; it moves no window.
            case let command as FocusCommand:
                command.args.boundaries == .allMonitorsOuterFrame || focusesWindowOnHiddenDesktop(command)
            case is WorkspaceBackAndForthCommand, is MoveNodeToMonitorCommand, is FocusMonitorCommand,
                 is MoveWorkspaceToMonitorCommand, is FocusBackAndForthCommand, is EnableCommand: true
            default: false
        }
    }

    /// `focus --window-id` for a window whose desktop is not showing switches there first,
    /// so it runs as navigation rather than inside the tiling fence.
    static func focusesWindowOnHiddenDesktop(_ command: FocusCommand) -> Bool {
        guard let id = command.args.windowId, let workspace = Window.get(byId: id)?.nodeWorkspace else { return false }
        return !workspace.isVisible
    }

}
