import AppKit
import Common

struct ModeCommand: Command {
    let args: ModeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        try await activateMode(args.targetMode.val)
        return true
    }
}
