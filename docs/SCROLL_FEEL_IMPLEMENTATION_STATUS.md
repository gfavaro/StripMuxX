# Scroll feel / free-size implementation status — 2026-11-15

**Experimental changes are committed to main; no Swift build, make check or physical trackpad tests were run.** The prior PASS WITH WARNINGS audit does not cover these commits.

## Shipped as source changes (not verified)

- `layout free-size` recognized by the CLI and permitted by the native tiling command fence.
- Free-size state is explicit on each window and remains part of the horizontal scrolling strip.
- A floating window can join as a free-size column without stretching to full height.
- Converting a stacked window to free-size extracts it into its own column.
- Free-size width uses fixed-column sizing; height and vertical placement follow the preferred native frame, clamped to the visible tile region.
- Native mouse resize updates free-size dimensions; trackpad/keyboard column resize preserves absolute-width mode.
- Converting back to floating retains the preferred window size; converting to tiling restores previous width preferences.
- Saved native Space layout snapshots now include optional free-size frame and prior column-width preferences, with backwards-compatible decoding.
- The minimap labels free-size columns.
- An explicit foreground close can activate a cross-app logical focus fallback when the original app has no remaining foreground window.
- Option + two-finger pan release no longer activates the nearest window. Only committed Dock swipes may select a different column.
- Stationary and nonfinite pan deltas no longer request redundant relayouts.
- Regression tests were added for snapshot restore, old layouts, native resize and pan focus behavior, but **not executed**.

## Not completed or independently verified

- No compilation, automated suite, native installation, or physical gesture testing.
- The full requested improvements to momentum feel, input-to-frame latency, automatic native close events, settings controls and multi-display recovery have **not** been validated or completed.
- Free-size geometry is based on a normal strip column; widths larger than the current display may still be clamped by existing geometry and macOS.
- No separate dynamic mode setting in Settings; `layout free-size` is the entry point.
- Gesture physics uses the existing macOS deltas and momentum; there is no new animation or scheduler rewrite.
- Synthetic tests cannot validate real Dock gestures, window titlebars or display hotplug.

## Memory hardening — 2026-11-15 (source-only, not compiled)

The native-space persistence layer was reviewed for lost strip and window state:

- After the restore grace period, a snapshot **stays protected** if zero saved
  windows can be matched; opening a completely unrelated app cannot overwrite
  the user's remembered strip.
- A native inventory that temporarily omits a Space **does not delete** its
  saved strip. This favors retention over automatically pruning snapshots of
  desktops intentionally deleted by the user.
- A saved floating window that reopens temporarily as tiled can be recovered
  when the app has exactly one unmatched saved and live window. Multiple
  ambiguous windows are not guessed or reordered.
- Regression tests cover no-match expiry, temporarily absent Space UUIDs,
  and an unambiguous floating window returning with a changed title.

Limits: there is no native window movement or activation in these fixes.
Ordinary floating windows remain outside the strip; their actual screen
coordinates are managed by macOS (StripMuxX does not force them to saved
absolute coordinates). After a *partial* restore with at least one match,
missing windows can still be dropped after the grace period. Hardware tests,
macOS restart validation, `make check`, and cross-monitor recovery were **not**
executed in this commit series. Do not carry forward the previous QA PASS
to this new HEAD.

## Validation required before release

1. Run `make check` and resolve any Swift compiler and test failures.
2. Test `layout free-size`, `layout tiling`, `layout floating` with real eligible app windows, including stacked windows.
3. Resize free-size windows by mouse and Option+Shift, then restart and compare native geometry.
4. Verify 33%, 50%, 100%, 150% and oversized scrolling, finger reversals, momentum, cancellation and no focus theft.
5. Test pinned columns, multi-display changes, sleep/wake, Mission Control and native Space switches.
6. Benchmark frame writes, AX timings, CPU and input latency before claiming a performance improvement.

If the new mode causes problems, return to `layout tiling` or `layout floating` for the affected window. Review `docs/SCROLL_FEEL_ACCEPTANCE.md` and update `docs/QA_AUDIT.md` **after** running the tests.
