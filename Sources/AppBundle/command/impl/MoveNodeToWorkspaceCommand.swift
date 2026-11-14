import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        await runtime.native.windowMoves.transferWindow(args, env: env, io: io)
    }
}
