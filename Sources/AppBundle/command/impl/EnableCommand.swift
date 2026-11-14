import AppKit
import Common

struct EnableCommand: Command {
    let args: EnableCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        try await runtime.native.setEnabled(args, io)
    }
}
