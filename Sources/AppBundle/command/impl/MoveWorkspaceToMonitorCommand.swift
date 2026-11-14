import AppKit
import Common

/// macOS cannot move a desktop to another display, so its windows and strip move instead.
struct MoveWorkspaceToMonitorCommand: Command {
    let args: MoveWorkspaceToMonitorCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        await runtime.native.windowMoves.transferDesktopContents(args, env: env, io: io)
    }
}
