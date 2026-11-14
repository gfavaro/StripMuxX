import AppKit
import Common

struct WorkspaceBackAndForthCommand: Command {
    let args: WorkspaceBackAndForthCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        await runtime.native.navigation.selectPreviousDesktop(io: io)
    }
}
