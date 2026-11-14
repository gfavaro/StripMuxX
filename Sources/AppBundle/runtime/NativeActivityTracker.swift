import Common
import Foundation
import NativeSpaces

/// Turns observations into history and hooks: each display's previous desktop for
/// back-and-forth, and the workspace, focus and focused-display hooks, all named by
/// desktop number.
@MainActor
final class NativeActivityTracker {
    private var activeByDisplay: [String: String] = [:]
    /// The desktop each display showed before its current one.
    private(set) var previousByDisplay: [String: String] = [:]
    private var focusedDisplay: String?
    private var focusedWindow: UInt32?
    /// The window focused before the current one, for `focus-back-and-forth`.
    private(set) var previousFocusedWindow: UInt32?
    private var hasStarted = false
    var runHooks: ([any Command], CmdEnv) -> Void = { commands, env in
        guard !commands.isEmpty, RunSessionGuard.isServerEnabled != nil else { return }
        let owner = runtime
        owner.task { _ = try? await commands.runCmdSeq(env, .emptyStdin) }
    }
    var execWorkspaceChange: (_ new: String, _ previous: String) -> Void = { runExecOnWorkspaceChange(new: $0, previous: $1) }

    /// Call after every observation and native focus synchronization; repeated
    /// calls with unchanged state do nothing.
    func observe(_ displays: [NativeSpaceDisplay], focusedDisplay display: String?, focusedWindow window: UInt32?) {
        guard !displays.isEmpty else { return }
        var changedDisplays: [(display: String, from: String, to: String)] = []
        for item in displays {
            if let old = activeByDisplay[item.identifier], old != item.activeSpaceID {
                if item.spaces.contains(where: { $0.id == old && $0.isDesktop }) { previousByDisplay[item.identifier] = old }
                changedDisplays.append((item.identifier, old, item.activeSpaceID))
            }
            activeByDisplay[item.identifier] = item.activeSpaceID
        }
        if !hasStarted {
            hasStarted = true
            focusedDisplay = display
            focusedWindow = window
            runHooks(config.afterStartupCommand, hookEnvironment(event: "startup"))
            return
        }
        func name(_ spaceID: String) -> String { NativeSpaceNavigation.desktopNumber(of: spaceID, in: displays).map(String.init) ?? "" }
        if let change = changedDisplays.first(where: { $0.display == display }) ?? changedDisplays.first {
            execWorkspaceChange(name(change.to), name(change.from))
        }
        if window != focusedWindow {
            if let focusedWindow { previousFocusedWindow = focusedWindow }
            focusedWindow = window
            runHooks(config.onFocusChanged, hookEnvironment(event: "focus-changed").withFocus(focus))
        }
        if display != focusedDisplay {
            focusedDisplay = display
            runHooks(config.onFocusedMonitorChanged, hookEnvironment(event: "focused-monitor-changed").withFocus(focus))
        }
    }

    /// The Space `workspace-back-and-forth` returns to on a display, if it still exists.
    func previousDesktop(on display: NativeSpaceDisplay) -> String? {
        previousByDisplay[display.identifier].flatMap { id in display.spaces.contains { $0.id == id } ? id : nil }
    }
}
