# StripMuxX Settings audit — 2026-11-14

This review compares visible settings with the implemented native-Spaces strip model.
It deliberately does **not** drop parser support or silently delete existing TOML keys.

## Keep in everyday Settings

- General: start at login, restore native strips, restore pre-tiling frames on quit,
  auto-reload config, setup check and diagnostics.
- Windows/Strip: auto-tile new windows; column width; edge preview; width presets;
  focus centering; keep opening height; minimap and its hold modifiers;
  Option-scroll and experimental three-finger horizontal Dock swipe.
- Appearance: macOS appearance, menu-bar display, inner/outer gaps and their live
  preview. Gaps matter both for tiled windows and usable strip bounds.
- Shortcuts: native desktop navigation, moving a window to a native desktop,
  keyboard modes and modifier-side control.
- Displays: connected display information and native desktop creation placement.

## Retain but clarify or deemphasize

| Setting | Audit decision | Reason |
| --- | --- | --- |
| `fullscreen-width` | **Keep, clarify** | Currently affects both a lone tiled window and managed fullscreen. It is not native macOS fullscreen, and <100% deliberately does not fill the screen |
| `single-window-alignment` | **Keep** | Only applies to lone columns, not to all strip columns |
| `scrolling.keep-window-height` | **Keep** | Allows unusual app windows to retain their opening height, without a new layout mode |
| `scrolling.edge-preview` | **Keep** | Explicitly controls side peeks separately from outer gaps; especially relevant with adjacent monitors |
| `scrolling.three-finger-swipe` | **Experimental** | Uses undocumented Dock event fields, requires physical testing and conflicts with other managers claiming the same swipe |
| Learned application minimums | **Collapse under Advanced** | Useful repair/evidence facility, not a routine layout preference |
| Display assignments | **Keep, label advanced** | Only determines where a *new* native Space is created; does not pin or move existing Spaces |
| Keyboard modes | **Keep** | A keyboard interaction layer, not a virtual workspace layout |

## Legacy compatibility, not everyday controls

- `exec-on-workspace-change`: legacy executable hook inherited from WinMux.
  Remove its direct editor field to avoid encouraging a misleading notion of
  virtual workspace changes. Preserve its parser and any existing user value.
  Existing users can inspect it in the raw TOML editor; audit its runtime
  dispatch separately before any deprecation/removal.
- `single-window-aspect-ratio`: legacy configuration fallback used only when
  `fullscreen-width` is unset; do not offer both as equally current controls.
- `workspace-to-monitor-force-assignment`: keep for desktop creation and
  clearly describe its limited effect.
- Virtual workspace layouts, Dwindle, BSP, tabs, projects, sidebar, hover bar,
  dimming and follow-focus mouse features are already removed/ignored through
  `RemovedConfiguration.swift`; do not restore these UI controls.

## Open follow-ups

1. Confirm whether the legacy `exec-on-workspace-change` hook is dispatched for
   native Space changes; migrate it to an explicitly named native-desktop event
   only after observing behavior in the running app.
2. Consider separating `fullscreen-width` into lone-window and managed-fullscreen
   preferences, but only as a deliberate breaking behavioral change.
3. Move display-assignment editing behind a dedicated advanced disclosure, once
   the live desktop movement workflow has a straightforward primary UI.
4. Recheck Settings search indexes whenever settings controls are renamed,
   and exercise live config saving / draft reconciliation on macOS.
