import AppKit
import Common

struct MoveNodeToMonitorCommand: Command {
    let args: MoveNodeToMonitorCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        await runtime.native.windowMoves.transferWindow(args, env: env, io: io)
    }
}

func windowIsntPartOfTree(_ window: Window) -> String {
    "Window \(window.windowId) is not part of tree (minimized or hidden)"
}
