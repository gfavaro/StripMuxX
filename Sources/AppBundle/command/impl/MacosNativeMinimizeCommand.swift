import AppKit
import Common

/// Asks macOS to minimize the window. It keeps its place on the strip and takes no room
/// until it is restored from the Dock.
struct MacosNativeMinimizeCommand: Command {
    let args: MacosNativeMinimizeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        window.asMacWindow().setNativeMinimized(true)
        return true
    }
}
