# SpaceMux reuse map

Each subsystem the brief names, what implements it today, and the recommendation.
Paths are under `Sources/` unless stated. All rows are **verified** by reading the
code at the cited location unless marked otherwise.

| Subsystem | Implementation | Evidence | Recommendation |
| --- | --- | --- | --- |
| Native Spaces discovery and identity | `NativeSpaces/NativeSpacesObservation.swift`, `NativeSpacesSnapshot.swift`, `NativeWorkspaceInventory.swift`; desktops keyed by UUID in `AppBundle/tree/NativeSpaceLayouts.swift:13` | Event-driven reads plus a 500 ms topology-only audit (`NativeSpacesObservation.swift:39`); a Space change revokes the current view before a new one is published (`NativeSpaceLayouts.reconcile`) | **Reuse** |
| Window discovery and lifecycle | `AppBundle/tree/MacApp.swift`, `AxWindowDiscovery.swift`, `AxWindowRegistry.swift`, `runtime/NativeWindowReconciler.swift` | AX observers per app (`layout/refresh.swift`, `refreshObs`); closure only on WindowServer destruction or process termination | **Reuse** |
| Window-to-Space assignment | `NativeSpaceLayouts.workspace(for:on:)`, `registrationDisplay(for:)` | Membership from the snapshot; windows on every desktop belong to the display under their centre | **Reuse** |
| Display management | `AppBundle/model/Monitor.swift` (`MonitorState`, line 84), `MonitorTopologyTest` | Immutable, Sendable monitor snapshots | **Reuse** |
| Accessibility operations | `MacApp.setAxFrame` (`tree/MacApp.swift:399`), `setAxFrameBlocking` (`:441`) | One AX thread per app with cancellable run-loop jobs per window (`MacApp.swift:30-31`, `:94`) | **Reuse** |
| Keyboard shortcuts | `AppBundle/config/HotkeyBinding.swift`, `SideFilteredHotkeys.swift:41`, modes in `ModeSession.swift` | Modes, taps, sequences, modifier sides | **Reuse** |
| Focus management | `AppBundle/focus.swift`, `runtime/NativeFocusHold.swift`, `NativeTilingCoordinator.synchronizeFocus` | Native focus with ownership lease | **Extend:** previous-column focus on close (Niri's `activate_prev_column_on_removal`) |
| Window positioning | `layout/layoutRecursive.swift` (`layoutWorkspace` :8, `layoutStrip` :39, `layoutColumn` :86), `layout/ColumnFrames.swift` | Writes only eligible windows under a current permit | **Reuse** |
| Frame corrections | `runtime/NativeFrameRecovery.swift` | Put-back after 150 ms of stillness (`:56`), at most three times per 10 s per tile | **Reuse;** extend with readback only if Phase 1 shows silent clamping |
| Scrolling geometry | `tree/ScrollingWorkspace.swift:62` `calculateScrollingWorkspaceGeometry` | Pure: value input, value output | **Reuse; extend** width model; add direct tests |
| Viewport policy | `ScrollingWorkspaceMetrics.focusedOffset` (`ScrollingWorkspace.swift:180`) | Reads global `config` by default; three call sites mutate `scrollingOffset` (`layout/layoutRecursive.swift:47`, `ui/ScrollingMinimapGeometry.swift:77`, `mouse/NativeScrollingPan.swift:126`) | **Refactor:** take mode as a value; one function for "focus landed on column" |
| Strip edits | `tree/StripEdits.swift`, `tree/normalizeContainers.swift`, `command/impl/*` | Covered by `StripCommandsTest` | **Reuse** |
| Commands and fence | `command/Command.swift` `runCmdSeq`, `runtime/NativeTilingCoordinator.swift:293`, `runtime/NativeCommandPolicy.swift` | Commands wait for readiness and are refused if their target changed | **Reuse** |
| Application lifecycle events | `GlobalObserver.swift`, `MacApp` registration, `NativeSpacesObservation` (session, wake, display events) | | **Reuse** |
| Desktop navigation | `runtime/NativeSpaceNavigator.swift` (Dock swipe, confirmed landing) | `NativeSpaceNavigatorTest` | **Leave unchanged** |
| Cross-desktop moves | `runtime/NativeWindowSpaceMoves.swift`, `NativeSpaces/NativeWindowSpaceMover.swift` (SkyLight, confirmed) | `NativeWindowSpaceMovesTest` | **Leave unchanged** |
| Trackpad pan | `mouse/NativeScrollingPan.swift` (Option + two-finger scroll, momentum) | `NativeScrollingPanTest` | **Reuse** |
| State persistence | `runtime/NativeLayoutPersistence.swift`, `tree/FrozenTreeNode.swift` (`FrozenStrip`) | Strip restored per UUID; pinned column saved; **viewport offset not saved** (`FrozenTreeNode.swift`, no offset field) | **Extend:** save the offset |
| Configuration | `config/parseConfig.swift`, `ScrollingConfig.swift:15`, `RemovedConfiguration.swift` | Schema and fixtures enforced by `make check` | **Extend** for new options only |
| Logging and diagnostics | `runtime/RuntimeEventRecorder.swift`, `RuntimeWorkMetrics.swift` (AX read/write/action, run-loop wait), `doctor`, `debug-windows` | | **Reuse** |
| Suspend mechanism | `enable off`, `RunSessionGuard` (`layout/refresh.swift`), `restore-frames-on-quit` | Pauses tiling and shortcuts; puts windows back | **Reuse** |
| Performance tooling | `script/profile_runtime.py` (read-only process sampling), `script/smoke.sh` | Measured idle baseline in [roadmap](implementation-roadmap.md#baseline) | **Reuse** |
| Tests | 458 XCTest cases plus Python checks (`make check`) | | **Extend** per [testing strategy](testing-strategy.md) |

Nothing in the audit calls for a rewrite. The two refactors (viewport policy as a
value-taking function, applied-frame readback) are local.
