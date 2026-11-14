# Usability pass — 2026-11-14

## Implemented

- Existing, validated three-finger horizontal scrolling remains unchanged.
- Size shortcuts now follow one mnemonic key family in the **reference config only**:
  Option+R cycles forward, Option+Shift+R cycles backward, Option+Command+R
  expands the current column to full width. Existing personal TOML bindings
  are not overwritten.
- Settings' managed fullscreen action now reads “Maximize in This Desktop”
  to distinguish it from macOS native fullscreen, and the column-full action
  explains it is not native fullscreen.
- The minimap footer responds to whether three-finger/Option-scroll gestures
  are enabled, instead of advertising an inactive gesture.
- Diagnostics counts all frame requests, requests routed through the scrolling
  gesture path, normal requests, and repeated normal targets. A repeated target
  is a **measurement**, not proof that AX can be skipped. No frame write was
  suppressed in this pass.

## Remaining priorities (require physical macOS verification)

1. Compare frame-request counts before and after a 10-second real three-finger
   pan; correlate with the existing scrolling layouts-per-second measurement.
2. Exercise minimap drag/reorder with 30–50 columns, pinned columns, and a
   display unplug or Space switch while dragging. Avoid making assumptions
   about events or window ownership during such transitions.
3. Confirm all shortcut additions in Accessibility, keyboard layouts, and
   application-specific conflict conditions; offer an opt-in preset migration
   rather than changing an existing user's bindings.
4. Audit minimap VoiceOver focus and contrast, especially keyboard selection
   in a horizontally scrolled canvas.
5. Decide whether “Full Column Width” and “Maximize in This Desktop”
   should share the same geometry; currently these are different commands.
