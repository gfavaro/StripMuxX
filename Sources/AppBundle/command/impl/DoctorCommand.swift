import AppKit
import Common

struct DoctorCommand: Command {
    let args: DoctorCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        if args.simulateNativePan { return io.out(await simulateNativePan()) }
        io.out(await buildDiagnosticsReport())
        return true
    }
}
