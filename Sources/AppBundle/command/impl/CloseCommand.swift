import AppKit
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        try await allowOnlyCancellationError { @MainActor @Sendable in
            guard let target = args.resolveTargetOrReportError(env, io) else { return false }
            guard let window = target.windowOrNil else {
                return io.err("Empty workspace")
            }
            // Access ax directly. Not cool :(
            if try await args.quitIfLastWindow.andAsync({ @MainActor @Sendable in try await window.macAppUnsafe.getAxWindowsCount() == 1 }) {
                let app = window.macAppUnsafe
                if app.nsApp.terminate() {
                    for workspace in Workspace.all {
                        for window in workspace.allLeafWindowsRecursive where window.app.pid == app.pid {
                            window.asMacWindow().garbageCollect()
                        }
                    }
                    return true
                } else {
                    return io.err("Failed to quit '\(window.app.name ?? "Unknown app")'")
                }
            } else {
                let workspace = window.nodeWorkspace
                let wasFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.pid
                window.closeAxWindow()
                if let workspace,
                   restoreLogicalFocusAfterWindowClosed(window.windowId, in: workspace),
                   wasFrontmost, !isUnitTest,
                   let fallback = focus.windowOrNil as? MacWindow,
                   fallback.app.pid != window.app.pid {
                    // A last-window close can leave a windowless app frontmost.
                    // Only an explicitly closed, previously frontmost window
                    // may activate the logical fallback in another app.
                    fallback.nativeFocus()
                }
                return true
            }
        }
    }
}
