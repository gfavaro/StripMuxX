import AppKit
import Common

struct FocusBackAndForthCommand: Command {
    let args: FocusBackAndForthCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        try await runtime.native.focusPreviousWindow(io)
    }
}
