# Scroll feel and free-size columns — implementation contract

Status: design contract; **not yet implemented or tested**. Branch `feat/scroll-feel-free-size`.
This document records the requested behavior before code changes and deliberately does
not redefine the existing floating behavior.

## Model

A window has three effective presentation modes:

| Mode | Member of scrolling strip | Horizontal placement | Size and vertical position |
| --- | --- | --- | --- |
| Tiled | Yes | Strip layout | Strip layout |
| Free-size | Yes | Strip layout | User-controlled, preserved |
| Floating | No | macOS/user | macOS/user |

Free-size is **opt-in**, and all existing floating rules, config files and saved
layouts retain their present meaning. A transient dialog remains floating.
Do not derive free-size from `Window.isFloating` (currently defined by direct
parentage to `Workspace`); it must have an explicit, persisted model state.
Within the strip, free-size windows should count as columns for navigation,
reordering, minimap and camera offset.

A free-size column should store its own desired width, height and vertical offset,
and should preserve these values across panning, focus changes, manual window
resizes, display changes and restart. Clamp *rendered* coordinates to display and
app limits without silently destroying saved preferences. On display resize,
recompute display-relative positioning and keep desired dimensions for restoration.
When converting free-size -> tiled -> free-size, restore the previously captured
free-size frame when valid. Do not invent nested/overlapping tiled layouts.

## Existing owners and integration points

- `Sources/AppBundle/tree/Window.swift`: currently has `lastFloatingSize`,
  `singleWindowManualWidth`, and `isFloating`; do not overload any of those
  as a free-size mode discriminator.
- `Sources/AppBundle/layout/ColumnFrames.swift`: currently honors
  `keepWindowHeight` for a lone window, but computes normal strip column widths.
  Do not modify this as a shortcut to free-size: mode-specific width and height
  must be reflected in both logical and physical strip geometry.
- `Sources/AppBundle/tree/StripEdits.swift`: preserve column widths and
  horizontal camera anchor when changing modes, inserting, and reordering.
- `Sources/AppBundle/tree/NativeSpaceLayouts.swift` and
  `Sources/AppBundle/runtime/NativeLayoutPersistence.swift`: extend existing
  versioned restore data, keeping old layouts readable.
- `Sources/AppBundle/ui/WorkspaceScrollingMinimap.swift`: distinguish modes
  without changing insertion and focus behavior.
- Existing commands, settings/config parser, schema and shortcuts remain the
  single authoritative interface. Only add user-facing controls when the
  implementation is complete.

## Scrolling interaction contract

1. Option + two-finger horizontal pan moves the *viewport*, not native focus.
   On live finger movement, input delta has a direct, sign-consistent mapping
   with no eased interpolation or implicit snap.
2. Momentum is separated from direct movement by native event phase. Reversal,
   missing lift, cancellation, app deactivation, Space change and display
   disconnect must reset owned gesture state predictably.
3. The post-lift result is the current clamped offset unless an explicitly
   configured future snap mode is enabled. Do not add hidden focus-on-release.
4. A focus command moves the camera only as far as needed to reveal its target,
   respecting the current center-focused-column preference.
5. Window resize preserves the selected anchor and does not move the camera
   unexpectedly. Option+Shift resize momentum must stay swallowed, as established
   by QA audit commit `fb185d71`.
6. Existing three-finger Dock gesture arbitration is separate from Option pan.
   Retain the current committed-wide-column assist unless physical tests show
   a better behavior; do not infer success from synthetic gestures.
7. Preserve pinned columns, native Spaces ownership and last-write-wins AX
   scheduling. Optimize only after measuring actual input-to-frame latency,
   AX calls and request counts.

## Compatibility and rollout

- Add a feature flag or opt-in command for free-size. Default to existing
  tiling/floating behavior; do not silently migrate floating windows.
- Persist mode and geometry with forward-compatible decoding and a regression
  for old snapshots.
- A failed AX write may temporarily prevent physical movement, but must not
  corrupt the logical strip or saved geometry.
- Prefer a small series of coherent, separately tested commits over a
  large gesture/scheduler rewrite.
- Run `make check` and native desktop acceptance *before* a release claim.

See `docs/SCROLL_FEEL_ACCEPTANCE.md` for the test and measurement gate.
