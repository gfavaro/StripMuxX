# Interaction research — Spear first, ChainYourMac second

This document defines the reference hierarchy for StripMuxX, not a claim that the
applications implement identical layouts.

## Product priorities

1. **Spear / 10/GUI — R. Clayton Miller.** Primary reference for the *interaction
   model*: direct spatial manipulation, moving between groups of windows,
   deliberate gestural mapping and interaction discoverability. The original
   10/GUI/Con10uum concept and the current Spear application must be studied
   separately. Spear's modern overlapping windows are deliberately **out of
   scope** for the scrolling-only engine.
2. **ChainYourMac.** Primary reference for operational behavior on real Macs:
   pinned columns, trackpad navigation, interactive strip overview, maintaining
   focus, native Spaces, monitor boundaries and recovering after sleep.
3. **Niri.** Behavioral oracle for scrolling-column geometry, focus movement,
   view offsets, column sizing and consume/expel semantics.
4. **OmniWM / Paneru.** Engineering references for macOS offscreen window
   constraints, parking, AX behavior and multi-display quirks.

## Source material to consult

- Spear official site: https://spearui.com/
- Clayton Miller's published updates: https://www.teapawt.net/claymill
  (his October 2026 posts explicitly describe Spear as an overlapping, non-tiling manager)
- Clayton Miller's project introduction and 10/GUI background: seek
  original published demos/interviews before specifying exact gestural behavior.
- ChainYourMac features: https://chainyourmac.com/
- ChainYourMac changelog: https://chainyourmac.com/changelog
- ChainYourMac documentation: https://chainyourmac.com/docs
- Niri: https://github.com/niri-wm/niri
- OmniWM: https://github.com/OmniNull/OmniWM
- Paneru: https://github.com/karinushka/paneru

Do not assert an undocumented Spear feature is already implemented. For each
behavior, record a source link and version/date when possible.

## Design principles

- The mouse/trackpad should manipulate a visible spatial object (column or
  viewport), not an arbitrary opaque workspace number.
- Gestures must have predictable direction, bounded effects, clear cancellation
  and no unexpected focus theft. Apple's native desktop gestures remain Apple's.
- The same operation should be discoverable and accessible through a keyboard
  command and, where appropriate, the minimap.
- Preserve column size and location across insertion/removal, and never reorder
  windows because a background process opened a new one.
- Avoid continuously repositioning windows when macOS rejects a frame.
- Respect native full screen, Mission Control, displays, Accessibility failures,
  Reduced Motion and the user's choice to float an application.

## Experiments and acceptance criteria

| Priority | Experiment | Acceptance |
| --- | --- | --- |
| P0 | Drag a minimap column to a new location | No focus theft or unrelated size change; reject stale drag targets after Space/topology changes |
| P0 | Pan independently of focus (keyboard) | Focus does not change; position is clamped and persisted |
| P0 | Restore camera position per native Space | Restart does not immediately recenter the saved viewport |
| P1 | Pinned column while panning nearby columns | Pinned frame stays stable; no window appears on another display |
| P1 | Gesture reversal and trackpad momentum | Gesture follows fingers; cancellation and settling predictable |
| P1 | Wake with two side-by-side displays | Layout stays on the correct display; no relocation loop |
| P2 | Animate motion when Reduce Motion is off | Animation may be interrupted; no per-frame AX storm |
| P2 | Spatial interaction prototype inspired by Spear | Opt-in, scrolling-only, evidence-backed, accessible |

## Deliberate non-goals

No overlapping tiling mode, tabbed layout, BSP/dwindle, new virtual workspaces or
private compositor. MacOS Spaces remain the sole workspace system.

## Engineering baseline

The project uses the existing pure strip geometry, one runtime owner on MainActor,
per-application AX workers and the native Space observation/fence. Do not
duplicate this architecture for an interaction feature.
