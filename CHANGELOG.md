# Changelog

## Unreleased

### Added
- The minimap shows where your windows are: a "Desktops" row of numbered buttons with the icons of the apps on each desktop (click to switch, as `workspace N` does), and with two or more displays a "Displays" row that pictures them as they are arranged, each with its desktop and apps (click to go there). An open minimap follows the desktop change, and a click anywhere outside it dismisses it.
- `scene-stripmuxx.sh`, bundled in the app's Resources, a hook for Scene (Settings → Scripts) that sets the root `accent-color` from the theme on screen and restores your own value afterwards. See the recipe in `docs/RECIPES.md`.
- Default keys for the previous window (`focus-back-and-forth`), focusing and moving a window to the neighbouring display, the first column, and window height ±50, in the default config and the ergonomic preset.
- Floating windows stay floating and are easy to find: the minimap lists them under the strip (click to focus), and `focus floating` (Alt-Shift-V) steps through them, then back to the strip window you left.
- `shortcuts` (Alt-Shift-/) shows the current mode's shortcuts, grouped, in macOS notation.
- Window rules can set a new window's column width: `scrolling-width <share>` (0.1 to 1) and `scrolling-width-pixels`. `scrolling-width <share>` also works as a shortcut.
- Windows ease toward the fingers during a scroll gesture (about 40 ms; off while Reduce Motion is on). On flick-shaped input this cut the border's 90th-percentile distance from a window edge from 139 pt to 22 pt, at the cost of windows running about 44 ms behind the fingers.
- Window borders with the WinMuxX renderer. Every border setting is searchable in Settings.
- `doctor` reports why borders were hidden and how many unchanged gesture steps were skipped.
- `debug-windows --gesture-trace-start/--gesture-trace-stop` records a real gesture (inputs and every window position) and `script/analyze_gesture_trace.py` reports lag, border distance and smoothness from it.

### Changed
- A lone window is limited by one `single-window-aspect-ratio` (width as a multiple of height; 0, the default, fills the width) on every display, instead of the `fullscreen-width` and `lone-window-width` percentages. The ratio, like the alignment, can be overridden per display in a `[display.<pattern>]` table, and is a Settings control. `fullscreen` always fills the display.
- Windows always ease toward the fingers over 40 ms (off while Reduce Motion is on); `gesture-smoothing` and `gesture-sensitivity` no longer exist. `fullscreen-width`, `lone-window-width` and those two keys are ignored with a note in `doctor` when a config still sets them.
- The minimap is compact: window cards sized to the strip at true scale (a 64 pt row; a window that keeps its own height or is free-size is drawn at its real height and position), an accent frame around the visible part, no scroller or position bar.
- Commands no longer force a full window reread when the model is current: `focus left/right` p50 81 → 48 ms.
- Window writes during a scroll gesture skip frames that did not change: 1008 → 107 writes for one pan with 48 columns.
- The cheat sheet and minimap free their window memory when closed.
- The commit hash is linked into the binaries; builds no longer rewrite a source file.

### Fixed
- The minimap drew every window at a different shape from the real one: tiles were all the same height with only their widths scaled, and one narrow column widened every tile by 1.27 times, so a full-width Safari window looked like a wide screen. Tiles now keep their windows' proportions and the viewport frame the display's; only an extreme column (under 16 pt on the map) raises the scale.
- Scrolling stutter: window motion during a gesture was uneven (47% of a window's position updates came more than 33 ms after the last, 28% more than 50 ms) because unfocused borders, transparent by default, were still positioned and redrawn on every display frame on the thread that receives scroll events, so events reached StripMuxX up to 128 ms late in bursts. Borders in a fully transparent colour are skipped, and the gesture's minimap is drawn after the event instead of inside it. Windows now update every 16.6 ms (no gap over 33 ms) and events reach the app in 0.08 ms at the median.
- Held-key navigation no longer drops about half its repeats (25 of 25 accepted at 33 ms).
- Borders no longer trail a scrolling window by 100 pt, stay off-position at the strip end, or blink after every read.
- Finder's windows are managed (macOS gives Finder no launch date).
- Momentum after an Option+Shift resize, and the lift of a resize the idle timer ended, no longer scroll the app under the pointer.
- A strip change made just before quitting or `enable off` is saved.
- A free-size window keeps its own width.
- Every compiler warning in the product code is cleared; errors in shortcut, menu-bar reload and startup tasks are logged instead of dropped.

### Removed
- The stale WinStrip planning documents (`docs/architecture`); the accurate events note is `docs/STATE_AND_EVENTS.md`.

- Add a task-based learning path and a detailed Dinky fit and execution plan.
- Add illustrated layout, command and configuration recipe guides.
- Preserve dangling configuration symlinks during bootstrap and round-trip quoted Unicode CLI arguments.
- Report side-filtered shortcut failures and retry event tap installation for a bounded period.

Released versions are listed on the [GitHub releases page](https://github.com/gfavaro/StripMuxX/releases).
