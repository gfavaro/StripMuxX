import AppKit
import Combine
import Common

/// AppKit can notify effectiveAppearance again while a status button is rendered.
/// Accept only actual scheme changes so rendering cannot feed its own observer.
struct MenuBarAppearanceGate {
    private var previous: NSAppearance.Name?
    mutating func accept(_ name: NSAppearance.Name) -> Bool {
        guard previous != name else { return false }
        previous = name
        return true
    }
}

@MainActor
public func installNativeMenuBar(checkForUpdates: (() -> Void)? = nil) {
    NativeActionMenu.shared.install(checkForUpdates: checkForUpdates)
}

@MainActor
final class NativeActionMenu: NSObject, NSMenuDelegate {
    static let shared = NativeActionMenu()
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var accessibilityObservation: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var checkForUpdates: (() -> Void)?
    private var bindings = ActionMenuBindings(mode: nil)
    private var appearanceGate = MenuBarAppearanceGate()
    private var lastModePresentation: ModePresentation?
    private var lastIconState: (enabled: Bool, appearance: MenuBarIconAppearance, indicator: MenuBarIndicator, text: String, name: String, stopped: String?)?
    private var capturedRuleTarget: QuickFloatingRuleTarget?

    func install(checkForUpdates: (() -> Void)?) {
        guard statusItem == nil else { return }
        self.checkForUpdates = checkForUpdates
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        if let button = item.button {
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { button, _ in
                Task { @MainActor in
                    let match = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
                    guard self.appearanceGate.accept(match) else { return }
                    menuBarIsDark = match != .aqua
                    self.lastIconState = nil
                    self.updateIcon()
                }
            }
        }
        accessibilityObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastIconState = nil
                self?.updateIcon()
            }
        }
        updateIcon()
        observation = TrayMenuModel.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    private func updateIcon() {
        let model = TrayMenuModel.shared
        let state = (enabled: model.isEnabled, appearance: model.menuBarConfiguration.iconAppearance, indicator: model.menuBarConfiguration.indicator, text: model.menuBarWorkspaceIndicator, name: model.menuBarWorkspaceName, stopped: model.menuBarTilingStoppedReason)
        if let previous = lastIconState, previous.enabled == state.enabled, previous.appearance == state.appearance, previous.indicator == state.indicator, previous.text == state.text, previous.name == state.name, previous.stopped == state.stopped, lastModePresentation == model.modePresentation { return }
        lastIconState = state
        lastModePresentation = model.modePresentation
        let mode = model.isEnabled ? model.modePresentation : nil
        let dark = statusItem?.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = mode?.color(dark: dark, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let modeDescription = mode.map { " · Mode: \($0.name)" + ($0.escapeReturnsToMain ? " · Esc to exit" : "") } ?? ""
        let stoppedDescription = state.stopped.map { " · \($0)" } ?? ""
        if model.isEnabled && state.indicator == .workspace {
            statusItem?.length = NSStatusItem.variableLength
            statusItem?.button?.image = nil
            let title = NSMutableAttributedString(string: state.text, attributes: [.foregroundColor: NSColor.labelColor])
            if let mode, let color { title.append(NSAttributedString(string: " | \(mode.initial)", attributes: [.foregroundColor: color])) }
            if state.stopped != nil { title.append(NSAttributedString(string: " ⏸", attributes: [.foregroundColor: NSColor.secondaryLabelColor])) }
            statusItem?.button?.attributedTitle = title
            statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            statusItem?.button?.toolTip = "StripMuxX · \(state.name) · Focused display" + stoppedDescription + modeDescription
            statusItem?.button?.setAccessibilityLabel("StripMuxX, \(state.name), focused display" + modeDescription)
            return
        }
        statusItem?.length = NSStatusItem.squareLength
        statusItem?.button?.attributedTitle = NSAttributedString(string: "")
        statusItem?.button?.setAccessibilityLabel(model.isEnabled ? "StripMuxX" + modeDescription : "StripMuxX disabled")
        let image = menuBarIconImage(
            enabled: model.isEnabled && state.stopped == nil,
            appearance: model.menuBarConfiguration.iconAppearance,
            keyboardTint: color,
        )
        image?.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "StripMuxX" + stoppedDescription + modeDescription
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        bindings = ActionMenuBindings(mode: activeMode.flatMap { config.modes[$0] })
        capturedRuleTarget = focus.windowOrNil.flatMap { window -> QuickFloatingRuleTarget? in
            guard let app = window as? MacWindow, let bundleId = app.macApp.rawAppBundleId else { return nil }
            return QuickFloatingRuleTarget(window: app, focus: focus, bundleId: bundleId,
                pid: app.macApp.pid, launchDate: app.macApp.nsApp.launchDate, workspaceId: focus.workspace.id)
        }
        let place = nativeDesktopNumber(of: focus.workspace).map { nativeDesktopDisplayName($0) } ?? "No space"
        menu.addItem(NSMenuItem(title: "StripMuxX · \(place)", action: nil, keyEquivalent: ""))
        if !runtime.native.tiling.ready {
            menu.addItem(NSMenuItem(title: runtime.native.tiling.status, action: nil, keyEquivalent: ""))
        }
        if activeMode != mainModeId {
            menu.addItem(NSMenuItem(title: "Mode: \(activeMode ?? "none")", action: nil, keyEquivalent: ""))
        }
        if TrayMenuModel.shared.shortcutHealth == .unavailable {
            menu.addItem(NSMenuItem(title: "⚠ Some keyboard shortcuts are unavailable", action: nil, keyEquivalent: ""))
            menu.addItem(callbackItem("View shortcut diagnostics…", #selector(openDiagnostics)))
        }
        let conflicts = runningOtherWindowManagers()
        if !conflicts.isEmpty {
            menu.addItem(NSMenuItem(title: "⚠ Other window managers: \(conflicts.joined(separator: ", "))", action: nil, keyEquivalent: ""))
            menu.addItem(callbackItem("Window management may conflict — view diagnostics…", #selector(openDiagnostics)))
        }
        // The top level shows state and quick switches; every other command lives in Commands.
        menu.addItem(.separator())
        addCommand("Center Column", script: "scrolling-center", to: menu)
        addCommand("Show Minimap", script: "scrolling-minimap", to: menu)
        addCommand("Cycle Column Width", script: "scrolling-width next", to: menu)
        addCommand("Pin Column Left", script: "scrolling-pin left", to: menu)
        addCommand("Pin Column Right", script: "scrolling-pin right", to: menu)
        menu.addItem(.separator())
        addCommand("Retile", script: "retile", to: menu, requiresWindow: false)
        addCommand("Balance Sizes", script: "balance-sizes", to: menu)
        addCommand("Fullscreen", script: "fullscreen", to: menu)
        menu.addItem(.separator())
        if let target = capturedRuleTarget {
            let appName = target.window.macApp.name ?? "This App"
            menu.addItem(callbackItem("Always Float “\(appName)”…", #selector(alwaysFloatApp)))
            let titleRule = callbackItem("Float Windows by Title…", #selector(floatThisWindow))
            titleRule.isAlternate = true
            titleRule.keyEquivalentModifierMask = .option
            menu.addItem(titleRule)
        }
        addSubmenu("Commands", to: menu) { addCommandsMenu(to: $0) }
        menu.addItem(.separator())
        menu.addItem(callbackItem("About StripMuxX", #selector(showAbout)))
        menu.addItem(callbackItem("Settings…", #selector(openSettings)))
        let enabled = addCommand("Enabled", script: "enable toggle", to: menu, requiresWindow: false, allowDisabled: true)
        enabled?.state = TrayMenuModel.shared.isEnabled ? .on : .off
        menu.addItem(callbackItem("Quit StripMuxX", #selector(quit)))
    }

    private func addCommandsMenu(to menu: NSMenu) {
        addSubmenu("Spaces", to: menu) { workspacesMenu in
            addCommand("Previous", script: "workspace prev", to: workspacesMenu)
            addCommand("Next", script: "workspace next", to: workspacesMenu)
            addCommand("Back and Forth", script: "workspace-back-and-forth", to: workspacesMenu)
            for (workspace, target) in menuWorkspaceTargets() {
                let item = addCommand(menuWorkspaceTitle(workspace), args: ["workspace", target], to: workspacesMenu)
                item?.state = workspace == focus.workspace ? .on : .off
            }
            workspacesMenu.addItem(.separator())
            addSubmenu("Move and Follow", to: workspacesMenu) { submenu in
                addCommand("Previous", script: "move-node-to-workspace --focus-follows-window prev", to: submenu)
                addCommand("Next", script: "move-node-to-workspace --focus-follows-window next", to: submenu)
                for (workspace, target) in menuWorkspaceTargets() {
                    addCommand(menuWorkspaceTitle(workspace), args: ["move-node-to-workspace", "--focus-follows-window", target], to: submenu)
                }
            }
            addSubmenu("Move Window to", to: workspacesMenu) { submenu in
                addCommand("Previous", script: "move-node-to-workspace prev", to: submenu)
                addCommand("Next", script: "move-node-to-workspace next", to: submenu)
                for (workspace, target) in menuWorkspaceTargets() {
                    addCommand(menuWorkspaceTitle(workspace), args: ["move-node-to-workspace", target], to: submenu)
                }
            }
        }
        if sortedMonitors.count > 1 {
            addSubmenu("Display", to: menu) { submenu in
                addCommand("Focus Previous", script: "focus-monitor prev", to: submenu)
                addCommand("Focus Next", script: "focus-monitor next", to: submenu)
                submenu.addItem(.separator())
                for (index, monitor) in sortedMonitors.enumerated() {
                    addCommand("Move Window to \(monitor.name)", args: ["move-node-to-monitor", String(index + 1)], to: submenu)
                }
            }
        }
        menu.addItem(.separator())
        for (title, command) in [("Focus", "focus"), ("Move Window", "move")] {
            addSubmenu(title, to: menu) { submenu in
                for direction in ["left", "down", "up", "right"] {
                    addCommand(direction.capitalized, script: "\(command) \(direction)", to: submenu)
                }
            }
        }
        addSubmenu("Stack With Column", to: menu) { submenu in
            addCommand("Left", script: "join-with left", to: submenu)
            addCommand("Right", script: "join-with right", to: submenu)
            addCommand("Unstack All", script: "flatten-workspace-tree", to: submenu, requiresWindow: false)
        }
        addSubmenu("Resize", to: menu) { submenu in
            for (title, script) in [("Wider", "resize width +50"), ("Narrower", "resize width -50"),
                                    ("Taller", "resize height +50"), ("Shorter", "resize height -50")] {
                addCommand(title, script: script, to: submenu)
            }
        }
        addCommand("Toggle Floating", script: "layout floating tiling", to: menu)
        addCommand("Undo Layout Change", script: "undo-layout", to: menu)
        if config.modes.count > 1 {
            addSubmenu("Mode", to: menu) { submenu in
                for mode in config.modes.keys.sorted() {
                    let item = addCommand(mode, args: ["mode", mode], to: submenu)
                    item?.state = mode == activeMode ? .on : .off
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(callbackItem("Refresh Spaces", #selector(refreshNativeSpaces)))
        addCommand("Reload Config", script: "reload-config", to: menu, requiresWindow: false, allowDisabled: true)
    }

    private func addSubmenu(_ title: String, to menu: NSMenu, build: (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        build(submenu)
        item.submenu = submenu
        menu.addItem(item)
    }

    @discardableResult
    private func addCommand(_ title: String, script: String, to menu: NSMenu, requiresWindow: Bool? = nil, allowDisabled: Bool = false) -> NSMenuItem? {
        guard case .cmd(let command) = parseCommand(script) else { return nil }
        return addCommand(title, command: command, to: menu, requiresWindow: requiresWindow, allowDisabled: allowDisabled)
    }

    @discardableResult
    private func addCommand(_ title: String, args: [String], to menu: NSMenu) -> NSMenuItem? {
        guard case .cmd(let command) = parseCommand(args) else { return nil }
        return addCommand(title, command: command, to: menu)
    }

    private func addCommand(_ title: String, command: any Command, to menu: NSMenu, requiresWindow: Bool? = nil, allowDisabled: Bool = false) -> NSMenuItem {
        let item = commandItem(title, commands: [command])
        let needsWindow = requiresWindow ?? menuCommandRequiresWindow(command)
        let accepted = runtime.native.accepts(command)
        item.isEnabled = accepted && (allowDisabled || TrayMenuModel.shared.isEnabled) && (!needsWindow || focus.windowOrNil != nil)
        applyBindings(bindings.bindings(for: command), to: item)
        menu.addItem(item)
        return item
    }

    private func commandItem(_ title: String, commands: [any Command]) -> NSMenuItem {
        let displayTitle = title.count > 140 ? String(title.prefix(140)) + "…" : title
        let item = callbackItem(displayTitle, #selector(runCommand(_:)))
        item.representedObject = MenuCommandPayload(commands: commands)
        item.toolTip = commands.prettyDescription
        item.isEnabled = TrayMenuModel.shared.isEnabled && (!commands.contains(where: menuCommandRequiresWindow) || focus.windowOrNil != nil)
        return item
    }

    private func applyBindings(_ matches: [ActionMenuBinding], to item: NSMenuItem) {
        if matches.count == 1, let binding = matches.first, let key = binding.keyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = binding.modifiers
        } else if !matches.isEmpty {
            item.title += "  [\(matches.map(\.notation).joined(separator: ", "))]"
        }
    }

    private func callbackItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuCommandPayload else { return }
        var environment = CmdEnv.defaultEnv
        if payload.commands.count == 1, payload.commands.first is CloseAllWindowsButCurrentCommand {
            environment = environment.withFocus(focus)
            let alert = NSAlert()
            alert.messageText = "Close other windows on this space?"
            alert.informativeText = "Applications may ask you to save unsaved changes. The focused window will stay open."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Close Other Windows")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let commandEnvironment = environment
        Task {
            do {
                guard RunSessionGuard.isServerEnabled(orIsEnableCommand: payload.commands.first) != nil || payload.commands.first is ReloadConfigCommand else { return }
                let result = try await payload.commands.runCmdSeq(commandEnvironment, .emptyStdin)
                if result.exitCode != 0 {
                    MessageModel.shared.message = Message(description: "Menu Command Error", body: (result.stderr + result.stdout).joined(separator: "\n"))
                }
            } catch {
                MessageModel.shared.message = Message(description: "Menu Command Error", body: String(describing: error))
            }
        }
    }

    @objc private func openSettings() {
        ShortcutSettingsModel.shared.requestWindowOpen()
    }
    /// The standard panel reads name, icon, version and build from the bundle; an accessory
    /// app must activate first or the panel opens behind the frontmost app.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutPanelCredits()])
    }
    @objc private func alwaysFloatApp() { createQuickFloatingRule(match: .application) }
    @objc private func floatThisWindow() { createQuickFloatingRule(match: nil) }

    private func createQuickFloatingRule(match requestedMatch: QuickFloatingRuleMatch?) {
        guard let target = capturedRuleTarget else { return }
        Task { @MainActor in
            let title = (try? await target.window.title) ?? ""
            let selectedMatch: QuickFloatingRuleMatch
            if let requestedMatch { selectedMatch = requestedMatch }
            else {
                guard !title.isEmpty else {
                    showQuickRuleMessage("This window has no title", details: "A title rule needs a nonempty window title.")
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Create a floating rule for this window?"
                alert.informativeText = "\(target.window.macApp.name ?? target.bundleId) · \(title)"
                let matchPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
                matchPicker.addItems(withTitles: ["Exact title", "Title starts with"])
                alert.accessoryView = matchPicker
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Create Rule")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                selectedMatch = matchPicker.indexOfSelectedItem == 1 ? .titlePrefix(title) : .exactTitle(title)
            }

            let configText: String
            do { configText = try ConfigFileStore.read(preferredEditableConfigUrl()) ?? "" }
            catch { showQuickRuleMessage("Could not read window rules", details: error.localizedDescription); return }
            if let conflict = QuickFloatingRuleDocument.conflict(in: configText, bundleId: target.bundleId,
                                                                  appName: target.window.macApp.name, title: title) {
                let details = conflict.actions.isEmpty ? "The earlier matching rule has no readable actions." : conflict.actions.joined(separator: " → ")
                let alert = NSAlert()
                alert.messageText = "An earlier window rule may match"
                alert.informativeText = "Rule \(conflict.ruleIndex + 1) runs first and stops further callbacks. Existing actions: \(details)"
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Open Configuration")
                if alert.runModal() == .alertSecondButtonReturn { openConfig() }
                return
            }

            let matchingWindows = MacWindow.allWindows.filter { $0.macApp.rawAppBundleId == target.bundleId }
            var matchingTitles: [String] = []
            for window in matchingWindows {
                let currentTitle = (try? await window.title) ?? ""
                guard !currentTitle.isEmpty else { continue }
                if QuickFloatingRuleDocument.matchesTitle(currentTitle, with: selectedMatch) { matchingTitles.append(currentTitle) }
            }
            let matchDescription: String
            switch selectedMatch {
                case .application: matchDescription = "all windows from this app"
                case .exactTitle(let value): matchDescription = "the exact title ‘\(value)’"
                case .titlePrefix(let value): matchDescription = "titles starting with ‘\(value)’"
            }
            let review = NSAlert()
            review.messageText = "Save floating rule?"
            review.informativeText = "App: \(target.window.macApp.name ?? target.bundleId) (\(target.bundleId))\nRule: \(matchDescription)\nCurrently matching windows: \(matchingTitles.isEmpty ? "none" : matchingTitles.joined(separator: ", "))"
            review.addButton(withTitle: "Cancel")
            review.addButton(withTitle: "Save Rule")
            guard review.runModal() == .alertSecondButtonReturn else { return }

            let rule = QuickFloatingRuleDocument.rule(bundleId: target.bundleId, match: selectedMatch)
            persistSettingsDocumentEdit(model: ShortcutSettingsModel.shared, settingIDs: ["on-window-detected"], onSaved: {
                guard target.isStillCurrent else {
                    self.showQuickRuleMessage("Rule saved", details: "The captured window changed before it could be floated. The rule will apply to future matching windows.")
                    return
                }
                guard case .cmd(let command) = parseCommand("layout floating") else { return }
                let environment = CmdEnv.defaultEnv.withFocus(target.focus)
                Task {
                    do {
                        _ = try await [command].runCmdSeq(environment, .emptyStdin)
                    } catch { self.showQuickRuleMessage("Rule saved, but the window could not be floated", details: error.localizedDescription) }
                }
            }, onFailure: { error in
                self.showQuickRuleMessage("Could not save floating rule", details: error.localizedDescription)
            }) { current in
                guard QuickFloatingRuleDocument.conflict(in: current, bundleId: target.bundleId,
                                                         appName: target.window.macApp.name, title: title) == nil else {
                    throw SettingsDisplayError("An earlier stopping window rule now matches. Review the rules before saving.")
                }
                return try QuickFloatingRuleDocument.adding(rule, to: current)
            }
        }
    }

    private func showQuickRuleMessage(_ title: String, details: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.runModal()
    }
    @objc private func openConfig() {
        NSWorkspace.shared.open(findCustomConfigUrl().urlOrNil ?? ((try? ensureBootstrapConfigExistsIfNeeded()) ?? preferredEditableConfigUrl()))
    }
    @objc private func openDiagnostics() { DiagnosticsWindowController.shared.show() }
    @objc private func refreshNativeSpaces() { runtime.native.observation?.requestRead() }
    @objc private func quit() { terminateApp() }

}

@MainActor
private struct QuickFloatingRuleTarget {
    let window: MacWindow
    let focus: LiveFocus
    let bundleId: String
    let pid: Int32
    let launchDate: Date?
    let workspaceId: WorkspaceId

    var isStillCurrent: Bool {
        var node: TreeNode? = window
        var currentWorkspace: Workspace?
        while let current = node {
            if let workspace = current as? Workspace { currentWorkspace = workspace; break }
            node = current.parent
        }
        guard MacWindow.allWindowsMap[window.windowId] === window,
              window.macApp.pid == pid, window.macApp.nsApp.launchDate == launchDate,
              window.macApp.rawAppBundleId == bundleId, currentWorkspace?.id == workspaceId,
              !window.macApp.nsApp.isTerminated else { return false }
        return true
    }
}

final class MenuCommandPayload {
    let commands: [any Command]
    init(commands: [any Command]) { self.commands = commands }
}

func menuCommandRequiresWindow(_ command: any Command) -> Bool {
    switch command {
        case is FocusCommand, is MoveCommand, is JoinWithCommand,
             is SwapCommand, is ResizeCommand, is LayoutCommand, is FullscreenCommand,
             is MoveNodeToWorkspaceCommand, is MoveNodeToMonitorCommand,
             is CloseCommand, is CloseAllWindowsButCurrentCommand,
             is MacosNativeMinimizeCommand, is MacosNativeFullscreenCommand: true
        default: false
    }
}

@MainActor
func menuWorkspaceTargets() -> [(workspace: Workspace, target: String)] {
    nativeDesktopWorkspaces().map { ($0.workspace, String($0.number)) }
}

@MainActor
func menuWorkspaceTitle(_ workspace: Workspace) -> String {
    userFacingDesktopName(workspace)
}

/// Credits under the version in the About panel: the fork, its upstream and the repository.
func aboutPanelCredits() -> NSAttributedString {
    let repository = "https://github.com/gfavaro/StripMuxX"
    let text = NSMutableAttributedString(
        string: "Personal fork by gfavaro of WinMux by Zimeng Xiong, MIT License.\n",
        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor],
    )
    text.append(NSAttributedString(string: "github.com/gfavaro/StripMuxX", attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .link: URL(string: repository)!,
    ]))
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
    return text
}
