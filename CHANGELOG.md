# Changelog

## Unreleased

### Added
- Floating windows stay floating and are easy to find: the minimap lists them under the strip (click to focus), and `focus floating` (Alt-Shift-V) steps through them, then back to the strip window you left.
- `shortcuts` (Alt-Shift-/) shows the current mode's shortcuts, grouped, in macOS notation.
- Window rules can set a new window's column width: `scrolling-width <share>` (0.1 to 1) and `scrolling-width-pixels`. `scrolling-width <share>` also works as a shortcut.
- Experimental `[scrolling] gesture-smoothing` (milliseconds, off by default): windows ease toward the fingers during a scroll gesture. On flick-shaped input, 40 ms cut the border's 90th-percentile distance from a window edge from 139 pt to 22 pt (80 ms: 1 pt) and made windows move in about four times as many steps, at the cost of windows running 44 ms behind the fingers and settling about 190 ms after release.
- Window borders with the WinMuxX renderer, and `borders.hide-while-scrolling` to hide them during a scroll gesture. Every border setting is searchable in Settings.
- `doctor` reports why borders were hidden, how long apps take to apply gesture writes, and unchanged gesture steps that were skipped.

### Changed
- The minimap is compact: icon cards sized to the strip, an accent frame around the visible part, no scroller or position bar.
- Commands no longer force a full window reread when the model is current: `focus left/right` p50 81 → 48 ms.
- Window writes during a scroll gesture skip frames that did not change: 1008 → 107 writes for one pan with 48 columns.
- The cheat sheet and minimap free their window memory when closed.
- The commit hash is linked into the binaries; builds no longer rewrite a source file.

### Fixed
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
