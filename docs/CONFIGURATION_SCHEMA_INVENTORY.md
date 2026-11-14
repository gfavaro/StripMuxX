# Configuration schema inventory

Source checked against `Sources/AppBundle/config/parseConfig.swift` and its
referenced parsers on 2026-11-14. The parser rejects
unrecognized keys, but skips keys and tables of WinMux features StripMuxX lacks
(`RemovedConfiguration.swift`); the schema flags those. Shared fixtures verify both.
TOML inline dotted keys and table headers can express equivalent structures.

| Root key / table | Accepted shape | Parser source / notes |
| --- | --- | --- |
| `config-version` | integer 1–2 | `parseConfigVersion` |
| `appearance` | `system`, `light`, `dark` | root parser |
| `after-startup-command`, `on-focus-changed`, `on-mode-changed`, `on-focused-monitor-changed` | command string or string array | `parseCommandOrCommands` |
| `exec-on-workspace-change` | string array | root parser |
| `start-at-login`, `auto-reload-config`, `automatically-tile-new-windows` | booleans | root parser |
| `persistent-workspaces` | string array; requires version 2 | numeric names are desktops to keep |
| `fullscreen-width` | number 0.1–1.0 | `WindowWidthConfig.swift` |
| `single-window-alignment` | `center`, `left`, `right` | root parser |
| `single-window-aspect-ratio` | scalar or monitor-specific dynamic value | legacy; used only without `fullscreen-width` |
| `display` | display patterns to width and alignment overrides | `WindowWidthConfig.swift` |
| `gaps` | nested inner/outer dynamic integer values | `parseGaps.swift` |
| `scrolling` | column width, width presets, centering, gesture and minimap settings | `ScrollingConfig.swift` |
| `native-spaces` | `restore-layouts`, `restore-frames-on-quit` booleans | root parser |
| `menu-bar` | indicator and icon appearance enums | `parseMenuBar.swift` |
| `modifiers` | modifier names mapped to `both`, `left`, `right` | `ModifierSides.swift` |
| `workspace-to-monitor-force-assignment` | desktop numbers to monitor-selector arrays | `parseWorkspaceToMonitorAssignment.swift`; chooses the display for added desktops |
| `on-window-detected` | array of matcher/run tables | `parseOnWindowDetected.swift` |
| `mode` | dynamic mode names; binding and mode settings | mode parsers and keyboard mapping |
| `key-mapping` | dynamic key names and mappings | key mapping parser |
| `exec` | command environment table | Exec config parser |
| removed features' keys and tables | anything | skipped and listed by `doctor` (`RemovedConfiguration.swift`) |

Defaults live in `Config.swift` and sub-config initializers. Conditional rules,
valid command strings, TOML version interactions, regex validity, monitor selector
resolution and cross-field constraints need the Swift parser/runtime.
