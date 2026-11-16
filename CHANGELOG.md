# Changelog

## Unreleased

### Added
- Floating windows stay floating and are easy to find: the minimap lists them under the strip (click to focus), and `focus floating` (Alt-Shift-V) steps through them, then back to the strip window you left.
- `shortcuts` (Alt-Shift-/) shows the current mode's shortcuts, grouped, in macOS notation.
- Window rules can set a new window's column width: `scrolling-width <share>` (0.1 to 1) and `scrolling-width-pixels`. `scrolling-width <share>` also works as a shortcut.
- Experimental `[scrolling] gesture-smoothing` (milliseconds, off by default): windows ease toward the fingers during a scroll gesture. On flick-shaped input, 40 ms cut the border's 90th-percentile distance from a window edge from 139 pt to 22 pt (80 ms: 1 pt) and made windows move in about four times as many steps, at the cost of windows running 44 ms behind the fingers and settling about 190 ms after release.
- Window borders with the WinMuxX renderer. Every border setting is searchable in Settings.
- `doctor` reports why borders were hidden and how many unchanged gesture steps were skipped.
- `debug-windows --gesture-trace-start/--gesture-trace-stop` records a real gesture (inputs and every window position) and `script/analyze_gesture_trace.py` reports lag, border distance and smoothness from it.

### Changed
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
