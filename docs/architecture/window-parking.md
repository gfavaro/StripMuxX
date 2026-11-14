# Window parking

"Parking" here means placing a column's windows when the column is scrolled out of
the viewport. Native Spaces remove the other half of the problem: windows on desktops
that are not showing are hidden by macOS, so StripMuxX never parks a whole workspace.

## Current behaviour (verified)

`calculateScrollingWorkspaceGeometry` (`tree/ScrollingWorkspace.swift:62`) gives every
column a logical frame on the strip and a separate physical frame:

- A column partly in view stays where it is, clamped so that at least the preview
  width remains on the display.
- A column wholly left or right of the viewport becomes an **edge preview**: placed so
  that 25 points of it remain visible at that display edge.
- On a side where another display is adjacent (a "wall"), the column is placed
  **inside** the display at that edge instead, behind visible columns in the stacking
  order, so it cannot cross onto the neighbouring display.
- Stacking order puts visible columns above parked ones and the focused column on top,
  enforced with AX raises (`layout/ScrollingWindowOrdering.swift`).
- Nothing is ever placed fully offscreen or in a screen corner.

## Reference findings

| Project | Technique | Source |
| --- | --- | --- |
| Paneru (MIT) | Offscreen columns keep a configurable sliver at the display edge, vertically inset; hidden virtual workspaces park 10 px inside the bottom-right corner. Stated reason: macOS reassigns a window whose frame leaves its display entirely to the display it lands on | `src/ecs/layout.rs` (`PARKED_STRIP_SLIVER`, `position_layout_windows`) |
| OmniWM (GPL-2.0) | Per monitor, chooses the hiding side by scoring which side has no neighbouring display; hides with a small edge-reveal epsilon; moves through SkyLight, writes AX frames once settled; re-parks when the observed frame drifts from the verified park frame | `LayoutRefreshController+HiddenWindowGeometry.swift` (`preferredHideSides`), `+WindowParking.swift` |
| Niri | Wayland compositor: no parking problem; windows outside the view are simply not drawn | `src/layout/scrolling.rs` |

All three macOS references converge on the StripMuxX rule: **keep part of every
window on its own display**. No `WindowParkingStrategy` abstraction is justified: the
rule is one pure function, already tested through commands.

## What is not yet evidenced

These are **assumptions** until Phase 1 measures them in this codebase:

1. Fully offscreen AX positions are clamped or reassigned by macOS (stated by Paneru;
   not reproduced here).
2. 25-point previews never trigger display reassignment in side-by-side, stacked
   (vertical) and offset display arrangements.
3. Apps with frame restrictions (minimum sizes, self-repositioning) keep preview
   placement; `NativeFrameRecovery` puts back an app that moves its window, at most
   three times per 10 s.
4. Clicking a preview raises and focuses the right window without the strip jumping.
5. Previews are not shown on the wrong desktop in Mission Control.

## Phase 1 proof of concept

A disposable fixture app (`script/native-spaces-fixture.swift`) with N windows on a
dedicated test desktop, driven through the dev build (`script/native-dev.sh`):

| Experiment | Measure | Pass |
| --- | --- | --- |
| Place a window 0, 1, 10, 25 px from fully offscreen, each edge | Actual frame read back; display ownership via `list-windows` | Frame equals request ±1 pt; window stays on its desktop |
| Same with a second display on each side, above and below | As above | No window changes display |
| Five windows in previews; click each | Focused window, strip offset | Focus lands on the clicked window; offset reveals it |
| Ten apps with known restrictions (Terminal, Safari, Finder, Electron, Java) | Put-back count, final frame | Within three put-backs; no oscillation |
| Mission Control open/close with previews | Visual check | Previews appear only on their desktop |

Decision after Phase 1: keep the 25-point rule, change the width, or add the
"inside the display" placement for every side ([ADR 0002](decisions/0002-parking-rule.md)).
