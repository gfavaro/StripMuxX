import AppKit
import Common

/// Shows the current mode's shortcuts over the focused display; run again to hide them.
struct ShortcutsCommand: Command {
    let args: ShortcutsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        if ShortcutCheatSheet.shared.isShown {
            ShortcutCheatSheet.shared.dismiss()
            return true
        }
        let sections = shortcutCheatSheetSections(activeMode.flatMap { config.modes[$0] })
        guard !sections.isEmpty else { return io.err("The current mode has no shortcuts") }
        ShortcutCheatSheet.shared.show(sections, on: focus.workspace.workspaceMonitor)
        return true
    }
}
