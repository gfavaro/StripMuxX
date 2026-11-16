# Contributor task map

Choose a starting point below, then trace current callers. Paths are relative to
`Sources/AppBundle` unless stated otherwise. Listed tests are starting coverage,
not evidence that every proposed change is covered.

| Task | Entry point and owner | Starting test filter | Done when |
| --- | --- | --- | --- |
| Strip command | `command/impl` (`MoveCommand.swift`, `JoinWithCommand.swift`, `FocusCommand.swift`, `ResizeCommand.swift`, `LayoutCommand.swift`); shared edits in `tree/StripEdits.swift`; shape in `tree/normalizeContainers.swift`; arguments in `Sources/Common/cmdArgs/impl` | `StripCommandsTest`, `ScrollingStripFeaturesTest` | Parsing, execution, failures and no-ops agree; the root's children stay columns and stacks never nest |
| Space navigation | `command/impl/WorkspaceCommand.swift` → `runtime/NativeSpaceNavigator.swift` | `NativeSpaceNavigatorTest` | A switch is reported only once a fresh read confirms it; bursts count from the switch in flight |
| Moves between spaces or displays | `runtime/NativeWindowSpaceMoves.swift` and the `move-node-to-*` / `move-workspace-to-monitor` commands | `NativeWindowSpaceMovesTest`, `NativeMonitorCommandsTest` | Moves are confirmed before a tree changes; both spaces' strips are checked |
| Tiling fence and command policy | `runtime/NativeTilingCoordinator.swift`, `NativeCommandPolicy.swift`, `NativeCommandTargetFence.swift` | `NativeTilingTest` | A command whose target changed during reconciliation is refused before it mutates anything |
| Observation and restart | `tree/NativeSpaceLayouts.swift`, `runtime/NativeWorkspaceLifecycle.swift`, `runtime/NativeLayoutPersistence.swift` | `NativeSpaceLayoutsTest`, `NativeTilingTest` | Strips stay with their space's UUID; saved strips survive restarts and are never overwritten while incomplete; fixtures never write real user state |
| Strip geometry | `layout/layoutRecursive.swift`, `ColumnFrames.swift`, `TileLayoutGeometry.swift`, `SingleWindowGeometry.swift` | `LayoutMinimumFitTest`, `SingleWindowGeometryTest`, `WindowWidthTest` | Unequal displays and application minima work; column widths and stacks are not rewritten by layout |
| Minimap and menu bar | `ui/WorkspaceScrollingMinimap.swift`, `ui/menubar` | `ScrollingMinimapTest`, `NativeActionMenuTest`, `ActionMenuTest` | Actual menus and the minimap reach the same commands as bindings |
| Settings save | `ui/settings/SettingsConfigPersistence.swift`, `SettingsSaveQueue.swift`, `ShortcutSettingsModel`; `config/ConfigFileStore.swift` | `SettingsSaveQueueTest`, `ShortcutSettingsConfigEditsTest` | Actual Settings destination writes valid TOML, reloads it and retains drafts on failure |
| Shortcut recovery | `config/HotkeyBinding.swift`, `SideFilteredHotkeys.swift`; runtime owns hotkey state | `HotkeyRecoveryTest`, `ModeLeaderTest` | Typing and mode transitions work; stale asynchronous work cannot restore obsolete state |
| New configuration option | `config/parseConfig.swift`, its section parser, `resources/default-config.toml` and the schema | `ConfigTest` and relevant section tests; `script/test_config_schema.py` | Parser, defaults, Settings/CLI consumers, schema and current docs agree; existing configurations retain intended meaning |
| Removed configuration | `config/RemovedConfiguration.swift` | `ConfigTest` | A key or command of a removed feature still loads, is skipped and is listed by doctor |
| Build, release or signing | `script/fork-build.sh`, `project.yml`, `makefile`; follow fork maintenance | `make check` and the affected Python release tests | Generated outputs are reviewed separately; identity/config/recovery remain intact; build is not reported as installation |

Run a relevant filter with `swift test --no-parallel --filter <Filter>`. Read
[Testing](TESTING.md) for setup and the full gate. Space and strip changes also
use [behavior examples](WORKSPACE_BEHAVIOR.md).

The `resources/`, `script/`, `project.yml` and `makefile` paths are repository-root
paths. For schema work, read [configuration schema inventory](CONFIGURATION_SCHEMA_INVENTORY.md).
For build changes, read
[fork maintenance](FORK.md) and [HACKING](../HACKING.md). The table is a starting map,
not an exhaustive catalog: use `rg --files` and `rg` when a file or symbol has moved.

## When a check fails

Distinguish compiler/setup errors, assertion failures and native behavior failures.
Read the first relevant error and the complete failing test. Compare expectations
with the user's requested behavior and current policy before changing production.
A newly written assertion can be wrong.

Use documented setup for missing dependencies. Reproduce a suspected existing
failure on an unchanged isolated baseline before calling it pre-existing. Do not
weaken assertions, skip failures, rerun until green or change dependency versions
solely to obtain a successful result.

If intended behavior is ambiguous, complete independent investigation and ask a
specific behavior question. Report environment blockers with the command, error,
completed checks and remaining work. Build, test, installation and space
validation are separate outcomes.

Stop broadening verification once the required checks pass unless a new change,
failure or unresolved concern justifies more work. Do not turn a small fix into a
general refactor. In a shallow clone, historical example commits may be absent;
use the linked current files or retrieve that commit if history is needed.

## Examples to study

These illustrate specific techniques, not blanket approval of every historical
implementation. Current testing guidance takes precedence over old patterns.

- **Ordered asynchronous saves:** read `Sources/AppBundleTests/ui/SettingsSaveQueueTest.swift`,
  especially `testScalarRawAndShortcutSavesShareOneOrderedQueue`. It injects access,
  holds an operation behind a gate, asserts observable order and releases the gate
  in cleanup. Bounded expectations establish completion without guessing via sleeps.
- **Confirmed native moves:** read `Sources/AppBundleTests/runtime/NativeWindowSpaceMovesTest.swift`,
  especially `testConfirmedMoveRehomesTheWindowIntoTheDestinationLayout` and
  `testUnconfirmedMoveIsReportedAndLeavesTheTree`. The tree changes only after
  macOS confirms the move, and a failure leaves both spaces as they were.

For preservation tests, assert live state: captured objects can remain intact even
if the application replaces them with a different tree.

## Completion report

State what changed and why, then report actual commands and results, nonzero test
counts, failures/skips and any remaining limitation. Report space checks separately.
Do not infer success from a truncated log or native correctness from mocks.
Documentation-only work reports link, example and formatting checks instead of
unrelated runtime tests.
