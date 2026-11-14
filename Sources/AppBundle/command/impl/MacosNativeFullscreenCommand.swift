import AppKit
import Common

/// Asks macOS to toggle fullscreen. The window keeps its place on the strip; the next
/// observation sees it leave for, or return from, its fullscreen Space.
struct MacosNativeFullscreenCommand: Command {
    let args: MacosNativeFullscreenCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        ScrollingWindowOrdering.shared.cancel()
        WorkspaceScrollingMinimap.shared.dismiss()
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let prevState = try await window.isMacosFullscreen
        let newState: Bool = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: !prevState
        }
        if newState == prevState {
            if !args.failIfNoop {
                io.err((newState ? "Already fullscreen. " : "Already not fullscreen. ") +
                    "Tip: use --fail-if-noop to exit with non-zero exit code")
            }
            return !args.failIfNoop
        }
        window.asMacWindow().setNativeFullscreen(newState)
        return true
    }
}
