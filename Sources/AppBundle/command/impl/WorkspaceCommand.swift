import AppKit
import Common
import Foundation

/// Switches the macOS desktop: `workspace N` follows Control-N numbering, next and prev
/// follow Control-arrow.
struct WorkspaceCommand: Command {
    let args: WorkspaceCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        await runtime.native.navigation.selectDesktop(args, io: io)
    }
}
