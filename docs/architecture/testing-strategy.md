# Testing strategy

[Testing](../TESTING.md) owns the mechanics (fixtures, isolation, `make check`). This
document maps the brief's areas to existing coverage and gaps.

| Area | Existing coverage | Gap / plan |
| --- | --- | --- |
| Pure layout calculations | Indirect only, through commands (`ScrollingStripFeaturesTest`, `LayoutMinimumFitTest`, `WindowWidthTest`) | **Add `ScrollingGeometryTest`:** table-driven input → frames, visibility, offset range; no runtime fixture |
| Column insertion and removal | `StripCommandsTest`, `testFocusAndMoveByPlaceOnTheStrip` | Insertion right of focus; focus after close (new behaviour) |
| Variable column widths | `ScrollingWorkspaceStateTest`, width presets | Fixed widths (if ADR 0003 approved) |
| Vertical stacking | `StripCommandsTest` (join, expel, normalize) | Height resize limits |
| Viewport positioning | `testCentreModes` | All three modes against Niri cases; scroll command |
| Focus navigation | `StripCommandsTest`, `NativeWindowSpaceMovesTest` (cross-display) | — |
| Resize constraints | `LayoutMinimumFitTest`, `LearnedWindowMinimumTest` | — |
| Offscreen parking | Geometry visibility classes via commands | Direct geometry cases per wall; Phase 1 physical experiments ([parking](window-parking.md)) |
| Native Space switching | `NativeSpaceNavigatorTest`, `NativeSpaceLayoutsTest` | Physical: trackpad swipes |
| Multi-monitor | `NativeMonitorCommandsTest`, `MonitorTopologyTest` | Physical two-display run |
| Display disconnect/reconnect | Topology reconciliation unit tests | Physical check |
| App startup/termination | `AppRegistrationRetriesTest`, `DestroyedWindowElementTest` | — |
| Native fullscreen | `testADisplayShowingAFullscreenSpaceHasNoDesktopAndCreatesNone` | Physical check |
| Mission Control | None automated | Physical check |
| Sleep/wake | None automated | Physical check |
| Accessibility permission loss | `HotkeyRecoveryTest` (partly) | Physical check: revoke while running |
| Stale window references | `DestroyedWindowElementTest`, `NativeTilingTest` (revoked targets) | — |
| Event ordering and concurrency | `NativeTilingTest`, `OverlappingRuntimeEventsTest`, `NativeFrameFaultTest` | — |
| Persistence and restoration | `NativeTilingTest` persistence cases | Viewport persistence |

## Physical validation matrix (manual, recorded separately)

Run with the dev build against a test desktop, one and two displays, with 5, 15 and
30 fixture windows: switching, moving across desktops and displays, previews,
Mission Control, fullscreen, sleep/wake, permission loss, restart. Record results
in the commit or a validation note; never infer them from unit tests.

## Performance measurements

`script/profile_runtime.py --pid <StripMuxX> --seconds 60` for idle; the same during a
scripted command loop for activity; `debug-windows --events-start` for AX call counts
(`RuntimeWorkMetrics`). Compare runs on the same machine only.
