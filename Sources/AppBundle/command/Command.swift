import AppKit
import Common

protocol Command: WinMuxAny, Equatable, Sendable {
    associatedtype T where T: CmdArgs
    var args: T { get }
    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool

    /// Queries read the established model and change nothing.
    var isQuery: Bool { get }
}

extension Command {
    var isQuery: Bool { false }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.args.equals(rhs.args)
    }

    nonisolated func equals(_ other: any Command) -> Bool {
        (other as? Self).flatMap { self == $0 } ?? false
    }
}

extension Command {
    var info: CmdStaticInfo { T.info }
}

extension Command {
    @MainActor
    @discardableResult
    func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        return try await [self].runCmdSeq(env, stdin)
    }

    var isExec: Bool { self is ExecAndForgetCommand }
}

// There are 4 entry points for running commands:
// 1. config keybindings
// 2. CLI requests to server
// 3. on-window-detected callback
// 4. Tray icon buttons
extension [Command] {
    /// Queries and Space-level commands run at once. Anything that edits a strip runs
    /// inside the tiling fence, which waits for the showing desktops to be reconciled and
    /// checks that the command's target is still the one it was given for.
    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ io: sending CmdIo) async throws -> Bool {
        if !NativeTilingCommandScope.active, contains(where: { !NativeCommandPolicy.runsOutsideNativeTilingFence($0) }) {
            return try await runtime.native.tiling.run(self, env: env, io: io)
        }
        var isSucc = true
        for command in self {
            if !runtime.native.accepts(command) {
                io.err("Command '\(command.args)' is not available")
                return false
            }
            if NativeTilingCommandScope.validateTarget?() == false {
                return io.err("The command's target changed during execution")
            }
            if NativeCommandPolicy.isNativeNavigation(command), !NativeTilingCommandScope.active {
                await runtime.native.awaitCurrentObservation()
            }
            let undoState = LayoutUndoHistory.shared.before(command)
            let commandSucc = try await command.run(env, io)
            if let undoState { LayoutUndoHistory.shared.commandFinished(undoState) }
            isSucc = commandSucc && isSucc
        }
        return isSucc
    }

    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        let io: CmdIo = CmdIo(stdin: stdin)
        let isSucc = try await runCmdSeq(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: isSucc ? 0 : 1)
    }
}
