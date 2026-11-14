import Common

/// Runs commands in order, stopping at the first failure; a Space switch must land
/// before focusing. Returns the failure's message.
@MainActor
func runUserCommands(_ commands: [String]) async throws -> String? {
    for text in commands {
        guard case .cmd(let command) = parseCommand(text) else { continue }
        let io = CmdIo(stdin: .emptyStdin)
        guard try await [command].runCmdSeq(.defaultEnv, io) else { return io.stderr.last ?? "\(text) failed" }
    }
    return nil
}
