import Foundation
import Common

struct ConfigurationReferenceSection: Identifiable {
    let id: String
    let title: String
    let description: String
    var defaults: String? = nil
    var example: String? = nil
    var pane: SettingsSidebarItem? = nil
}

@MainActor
var configurationReferenceSections: [ConfigurationReferenceSection] {
    let defaults = defaultConfig
    return [
        .init(id: "general", title: "General", description: "start-at-login launches StripMuxX at login. auto-reload-config watches the configuration file for changes.", defaults: "start-at-login = \(defaults.startAtLogin), auto-reload-config = \(defaults.autoReloadConfig)", pane: .general),
        .init(id: "workspaces", title: "Desktops", description: "persistent-workspaces lists stable desktop numbers; missing ones are added automatically.", defaults: "persistent-workspaces = []", example: "persistent-workspaces = ['1', '2', '3']", pane: .workspaces),
        .init(id: "scrolling", title: "Scrolling strip", description: "Configures column widths, edge preview, keep-window-height and the minimap.", defaults: "column-width = \(defaults.scrolling.columnWidth), gesture-enabled = \(defaults.scrolling.gestureEnabled), minimap-enabled = \(defaults.scrolling.minimapEnabled), keep-window-height = \(defaults.scrolling.keepWindowHeight)", example: "[scrolling]\ncolumn-width = 0.5\nwidth-presets = [0.3333, 0.5, 0.6667, 1.0]", pane: .windows),
        .init(id: "windows", title: "Windows", description: "Controls automatic new-window tiling and single-window size/alignment. lone-window-width controls a lone tiled column; fullscreen-width controls managed fullscreen. If lone-window-width is omitted, it falls back to fullscreen-width.", defaults: "automatically-tile-new-windows = \(defaults.automaticallyTileNewWindows), single-window-alignment = '\(defaults.singleWindowAlignment.rawValue)'", pane: .windows),
        .init(id: "appearance", title: "Appearance", description: "[gaps] controls spacing. Root appearance chooses system, light or dark for StripMuxX UI. [menu-bar] indicator chooses icon or workspace; icon-appearance chooses color or monochrome.", defaults: "appearance = '\(defaults.appearance.rawValue)', indicator = '\(defaults.menuBar.indicator.rawValue)', icon-appearance = '\(defaults.menuBar.iconAppearance.rawValue)'", pane: .appearance),
        .init(id: "modifier-sides", title: "Modifier sides", description: "[modifiers] accepts alt, cmd, ctrl and shift with both, left or right. Applies to shortcut chords; modifier taps retain their explicit sides. The unused side passes through for normal typing.", defaults: "All modifiers use both sides.", example: "[modifiers]\nalt = 'left'"),
        .init(id: "rules", title: "[[on-window-detected]]", description: "Match exact app-id, app-id-regex, workspace, app-name-regex-substring, window-title-regex-substring or during-winmux-startup (legacy name). Rules run in file order; check-further-callbacks = true continues after a match.", defaults: "No rules; check-further-callbacks = false.", example: """
        [[on-window-detected]]
        if.app-id = 'com.apple.finder'
        check-further-callbacks = false
        run = 'layout floating'
        """),
        .init(id: "assignments", title: "[workspace-to-monitor-force-assignment]", description: "Assign desktop numbers to displays. Display selectors include uuid:<UUID>, hardware:<vendor>:<model>:<serial>, main, secondary, display numbers and name patterns. Native Spaces uses them to place new desktops.", defaults: "No forced assignments.", example: """
        [workspace-to-monitor-force-assignment]
        '1' = 'main'
        '2' = 'secondary'
        """),
        .init(id: "window-width", title: "Lone-window and fullscreen width", description: "lone-window-width and fullscreen-width accept 0.1 to 1.0 globally or per display. If lone-window-width is omitted, the old fullscreen-width value still sizes lone windows. single-window-alignment accepts center, left or right for lone tiled windows; fullscreen stays centered.", example: """
        fullscreen-width = 1.0
        lone-window-width = 0.70
        single-window-alignment = 'center'
        [display.'Built-in']
        lone-window-width = 0.65
        """, pane: .windows),
        .init(id: "gaps", title: "Per-display gaps", description: "Each [gaps] value accepts a constant or an ordered list of display overrides followed by a fallback. Values are measured in points. Replace the existing key inside [gaps].", defaults: "See Appearance for the default inner and outer spacing.", example: """
        [gaps]
        inner.horizontal = [{ monitor.main = 4 }, 8]
        outer.left = [{ monitor.secondary = 12 }, 8]
        """, pane: .appearance),
        .init(id: "keyboard", title: "[key-mapping] and shortcut modes", description: "Keyboard presets: qwerty, dvorak or colemak. [key-mapping.key-notation-to-key-code] adds custom key names. [mode.<name>.binding] defines command shortcuts and sequences; hyper means alt-ctrl-cmd-shift and meh means alt-ctrl-shift; [mode.<name>.binding-tap] defines tap-only shortcuts.", defaults: "qwerty; no custom key mappings.", example: """
        [key-mapping]
        preset = 'qwerty'

        [key-mapping.key-notation-to-key-code]
        mykey = 'a'

        [mode.main.binding]
        alt-mykey = 'focus left'
        """, pane: .shortcuts),
        .init(id: "automation", title: "Automation callbacks", description: "after-startup-command runs after startup. on-focus-changed, on-focused-monitor-changed and on-mode-changed run after the corresponding focus or mode changes. They accept a StripMuxX command or an array of commands. exec-on-workspace-change is a legacy compatibility key best edited in the raw configuration.", defaults: "on-focused-monitor-changed = \(tomlStringArray(defaults.onFocusedMonitorChanged.map { $0.args.description }.joined(separator: "\n"))); other callbacks are empty.", example: """
        on-display-changed = []
        on-focus-changed = []
        on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
        on-mode-changed = []
        after-startup-command = []
        """, pane: .automation),
        .init(id: "exec", title: "[exec] and [exec.env-vars]", description: "Commands inherit the app’s environment. When [exec] is omitted, PATH receives /opt/homebrew/bin:/opt/homebrew/sbin before the inherited PATH. Defining [exec] replaces that implicit configuration; add PATH explicitly to retain the prefix. Variables support ${NAME} interpolation.", defaults: "inherit-env-vars = true; Homebrew PATH prefix when [exec] is absent.", example: """
        [exec]
        inherit-env-vars = true

        [exec.env-vars]
        PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}'
        """),
    ]
}
