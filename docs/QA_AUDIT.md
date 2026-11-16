# StripMuxX QA, regression and stability audit — 2026-11-14

**Verdict: PASS WITH WARNINGS.** `make check` passes (508 XCTest cases, 53 Python
checks). Seven defects were fixed; one P1 (unchecked pushes) and several P2 risks remain, and the physical
checks in [not executed](#7-not-executed) still need you at the desktop.

## 1. Environment

| | |
| --- | --- |
| macOS | 27.2.1 (26B131), Apple Silicon, one built-in display (2560 × 1664 Retina, 1710 points wide) |
| Toolchain | Apple Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| Running app during measurements | StripMuxX build 34 (`757c89bf`), 5 windows on desktop 1 |

## 2. Commit and branch

Branch `main`. Audited from `757c89bf` (merge of `origin/main` at `8cf47d4c` with the
unpushed `9d448054`, "Never create desktops from workspace shortcuts"). Fixes are in
`faa85330` … `72576197`, plus the edge-preview floor after the follow-up
measurement (see [§5](#5-bugs-found-and-fixed) and [§8](#8-remaining-risks)).

## 3. Commands executed

```sh
git status -sb; git log --oneline -1
make check                                   # three times: before, during, after fixes
swift test --no-parallel --filter <Suite>    # per suite while fixing
./.deps/config-schema/bin/python script/test_config_schema.py
python3 script/profile_runtime.py --pid $(pgrep -x StripMuxX) --seconds 60 --interval 5 --output <dir>
stripmuxx doctor                             # frame-request counters, before and after the idle profile
xcrun swift winframes.swift                  # read-only CGWindowList bounds of the managed windows
```

Each new or corrected test was mutation-checked: the production rule it guards was
broken on purpose, the test was seen to fail, and the code was restored.

## 4. Test results

| Run | XCTest | Python | Result |
| --- | --- | --- | --- |
| Initial `make check` | not reached | schema check failed | **FAIL**: `lone-window-width` missing from schema |
| After schema fix | 504 run, **6 failures** | pass | FAIL |
| `make check` after fixes 1–6 | 507 run, 0 failures | 53 run, 0 failures | PASS |
| Final `make check` (with fix 7) | **508 run, 0 failures** | 53 run, 0 failures | **PASS** |

Compiler warnings: 31 unique, none errors. Notable: 9 unused `Task` results
(fire-and-forget tasks whose errors are dropped), one main-actor property read from a
`Sendable` closure (`ShortcutSettingsView.swift:56`), one deprecated `String(cString:)`
(`appBundleUtil.swift:22`), 3 unnecessary `nonisolated(unsafe)`.

## 5. Bugs found and fixed

| # | Defect | Root cause | Fix | Test |
| --- | --- | --- | --- | --- |
| 1 | `make check` failed before running any Swift test | `lone-window-width` added to the parser but not the schema | `faa85330`: key at root and in display tables | New shared fixture |
| 2 | StripMuxX created desktops up to 9 at launch | A config without `config-version = 2` used AeroSpace's rule that every `workspace N` shortcut is a persistent workspace | `9d448054`: only an explicit `persistent-workspaces` list adds desktops | `testWorkspaceShortcutsNeverMakeDesktopsPersistent` |
| 3 | Parked columns were put back over and over | macOS keeps ≥ 40 pt of a window on its display (requested x = 1710, measured 1670); put-back saw them off their tiles and rewrote them, up to 3× per tile after each layout. `retile` already skipped them | `f3db8877`: put-back and retile share one rule, `frameRecoveryApplies(to:)` | `testParkedColumnsAreNotPutBackButVisibleAndOnlyTiledOnesAre` |
| 4 | Settings search for "single-window width" found nothing | The setting was renamed *Lone window width*; search matched titles only | `4f5fd111`: search aliases for earlier names | `SettingsSearchTest` |
| 5 | Two tests asserted AppKit side effects, not behaviour | `needsDisplay` is not kept for a view outside a window and used to be set by unconditional frame reassignment; `performClick` needs `NSApp` | `ee4fbfb1`: assert the tile's icons; create `NSApp` in setup | Minimap suite passes alone and in full |
| 6 | Three tests contradicted intended defaults | 8 pt side gaps, 0.5 default column width, and an edge-preview test whose claims never matched the geometry it shipped with | `993e9519`: corrected expectations; 50-column stress case | `ScrollingGeometryTest` |

| 7 | `edge-preview = 0` showed 40 pt slivers; desired frames never matched real ones | macOS moves a window placed wholly off its display back to show 40 pt, while honouring any sliver of 1 pt or more (measured, §8) | `41cd667f`: the layout keeps at least 1 pt on screen (`effectiveEdgePreview`) | `testAZeroPreviewStillLeavesOnePointSoMacOSDoesNotPullTheWindowBack`; confirmed on your windows with build 36 |

Also: the Settings column section did not compile (`64d90510`, pushed earlier);
an unused binding warning in `SingleWindowGeometry.swift` (`72576197`).

## 6. Performance

**Method:** `script/profile_runtime.py` samples the running process every 5 s for 60 s
through `proc_pid_rusage` (read-only; no windows opened, no AX queries). Frame-request
counters from `doctor` were read before and after.

| Measurement (5 windows, 1 desktop, 1 display, idle) | Value |
| --- | --- |
| Frame requests during 60 s idle | **0** (1,365 before and after) |
| Wakeups | 40 in 60 s (≈ 0.7/s) |
| CPU | 0.0 s recorded: the app was idle; macOS may have napped it, so treat as "below resolution" |
| Memory footprint | 30.9 MiB, delta −0.02 MiB over 60 s |
| Repeated normal frame targets since launch | 0 of 430 |

**Load test (build 35, run with permission):** a disposable fixture app opened N
plain windows on desktop 1 beside your 5; 40 alternating `focus left/right` and 10
`scrolling-width next` were sent through the CLI; CPU from `ps`, frame requests from
`doctor`; the fixture was then quit.

| Managed windows | Focus latency p50 / p90 / max | CPU for 50 commands | Frame requests per command | RSS |
| --- | --- | --- | --- | --- |
| 5 (your apps only) | 143 / 219 ms (20 commands) | — | — | — |
| 20 (15 fixture) | 79 / 106 / 183 ms | 2.79 s | 21.6 | 92 → 93 MiB |
| 35 (30 fixture) | 174 / 178 / 225 ms | 4.38 s | 37.1 | 93 → 90 MiB |

CLI round trip without layout (`list-modes`): 26 ms median, included above. Latency is
dominated by how fast apps answer AX, not by window count alone: your five real apps
are slower than twenty fixture windows. Each command rewrites roughly every window on
the strip (37 requests at 35 windows), because scrolling moves every visible column.
No crash; memory flat; StripMuxX returned to your 5 windows after each run.

**Smoke test (`script/smoke.sh`, build 35):** 13 pass, 0 fail, 3 skip (second desktop
or display needed). Put-back, the three-try limit, `retile`, app quit and focus return
pass; scrolling pan p90 lag 37 ms.

Frame-write pipeline (reviewed, verified in code): one AX thread per app, one pending
write per window (latest wins), writes cancelled on invalidation, permits checked per
write. Dinky's `FrameScheduler`/`FrameApplier` were not re-compared in this pass; no
change to the pipeline is proposed without a measured gap.

## 7. Not executed

| Area | Why |
| --- | --- |
| Two displays, display disconnect, sleep/wake | One display attached; sleep needs you at the machine |
| Space switching, moving windows across Spaces | Only one desktop exists and creating Spaces is out of bounds; automated simulations pass (`NativeSpaceNavigatorTest`, `NativeWindowSpaceMovesTest`) |
| StripMuxX restart with layout restoration on real apps | Restarted for each install (layout came back with 5 windows, tiling active) but not checked column by column |
| Three-finger gesture, Mission Control interplay | No synthetic Dock gestures without permission; you validated the gesture manually; code unchanged |
| VoiceOver, Reduce Motion, keyboard-only Settings walk-through | Manual UI checks |
| Settings persistence across an app update | Requires installing over a customised config; the save path is covered by `SettingsPersistenceRegressionTest` |

## 8. Remaining risks

**P0:** none found.

**P1**
- ~~Edge preview below 40 pt is not honoured.~~ **Corrected by measurement and fixed.**
  Moving a floating fixture window with AX showed macOS honours any sliver of 1 pt or
  more exactly, on both edges (1, 2, 3, 5, 14, 25, 40, 60 pt requested and read back);
  only a window placed wholly off the display is moved back to show 40 pt. The default
  14 pt was always fine; only `edge-preview = 0` produced 40 pt slivers. The layout now
  keeps at least 1 pt on screen (`effectiveEdgePreview`).
- **Unpushed work from other sessions.** Commits reached `main` without `make check`
  passing (build break, six failures). A pre-push `make check` would prevent this.

**P2**
- Outer columns are 4 pt wider than inner ones at the same width share (only inner
  edges give up half a gap).
- Focus after closing a window is left to macOS; Niri returns to the previous column.
- 15 default shortcuts shadow common macOS keys: Option + H/J/K/L/N/P/R/C/−/= (typed
  characters), Cmd-Shift-H/L/I (Finder, Safari), Ctrl-H/L (text editing). No duplicate
  bindings and every binding parses.
- `script/install_fork.py` requires Screen Recording, which StripMuxX does not use, so
  every install so far has been done by hand.
- Nine fire-and-forget `Task`s drop their errors.
- Command latency of 80–220 ms per focus change, driven by app AX response time;
  every command rewrites the visible strip. Worth profiling which AX calls dominate
  before changing the pipeline.

## 9. Recommended next actions

1. Run the §7 physical matrix on a test desktop with `script/native-spaces-fixture.swift`.
2. Relax the installer's Screen Recording requirement.
3. Offer an opt-in shortcut preset that avoids Option-letter keys (for example
   `modifiers.alt = 'left'` plus Ctrl-Option chords), without changing existing bindings.
4. Run `make check` before every push.

## 10. Post-audit delta (not part of the original PASS WITH WARNINGS verdict)

After the baseline audit, further commits added logical focus-on-close fallback,
non-interactive native-window drag placeholders, minimap insertion hints, and
three-finger gesture diagnostics. These changes are **not** covered by the
original 508/53 test evidence. See [single-pass beta verification](BETA_VERIFICATION.md)
for required final automated and physical checks. Do not carry forward the old
PASS verdict to newer commits until the final workflow completes.

---

# Final beta validation — 2026-11-15

**Recommendation: PASS WITH WARNINGS.** No P0 or P1 defects found; no code changes
were needed. Real trackpad gestures, multi-desktop and multi-display behaviour, and
restart restoration were **not** exercised physically (see below); CI and the tests
here do not validate real gestures.

## Tested build

| | |
| --- | --- |
| Commit | `eb05e65e06522746c9373cf33fa111f1a01f8967` on `main` (installed as build 38; identical code to build 37) |
| Working tree | clean except the pre-existing `legal/LICENSE.txt` type change (symlink → identical file) |
| Environment | macOS 27.2.1 (26B131), Apple Silicon, one built-in display (1710 pt wide), one desktop; Apple Swift 6.4.2 |
| Commits reviewed since the first audit | 20 (`c519e658` … `eb05e65e`) |

## Commands

```sh
make check
python3 script/profile_runtime.py --pid $(pgrep -x StripMuxX) --seconds 30 --interval 5 --output <dir>
stripmuxx focus left|right | focus --window-id N | close [--window-id N]   # against fixture windows
stripmuxx doctor                                                           # frame-request counters
dragtest <x> <y> <dx> full|nomouseup|up    # CGEvent mouse drag on a fixture title bar (scratch tool)
```

Fixture windows came from a disposable app (`LoadFixture`, scratchpad only) opening N
plain windows; it was quit after each run. Your work windows were not moved, closed
or focused except for restoring the original focus afterwards.

## Automated results (executed)

| Suite | Run | Passed | Failed | Skipped |
| --- | --- | --- | --- | --- |
| XCTest (`make check`) | 520 | 520 | 0 | 0 |
| Python checks (`make check`) | 59 | 59 | 0 | 0 |
| Compiler warnings | 29 unique | — | — | — |

## Physical tests (executed on this Mac)

| Area | Result |
| --- | --- |
| Close focused window after A → B → C | Focus went to B; frontmost app unchanged; Space unchanged |
| Close unfocused windows (A, then C) while B focused | Focus stayed on B; no app activated |
| Close an app's last window | Logical focus fell back to another app's window on the desktop while macOS kept the (now windowless) app frontmost; **nothing was activated** (P2 below) |
| Drag a tiled window, normal mouse-up | 0 overlays after release; window returned to its tile |
| Drag with mouse-up withheld | 1 overlay during the drag; 0 within 4 s (3 s expiry) |
| First drag after focusing | No preview shown (likely the first press only focused the window); not reproduced on the next drag |

## Performance (executed; 100 alternating `focus` commands per size)

| Managed windows | p50 / p90 / p99 | Frame requests per command | Repeated targets | Main-process CPU per command | RSS | Idle 30 s: wakeups / CPU / footprint |
| --- | --- | --- | --- | --- | --- | --- |
| 6 (your apps) | 101 / 129 / 276 ms | 6.4 | 0 | 60 ms | 53 MiB | 32 / 0.001% / 22.7 MiB |
| 21 | 93 / 102 / 138 ms | 21.6 | 0 | 61 ms | 53 MiB | 43 / 0.001% / 23.0 MiB |
| 36 | 119 / 127 / 136 ms | 36.3 | 0 | 74 ms | 54 MiB | 33 / 0.001% / 23.0 MiB |
| 51 | 147 / 157 / 172 ms | 51.5 | 0 | 88 ms | 54 MiB | 35 / 0.001% / 23.3 MiB |

Latency includes a 26 ms CLI round trip. Requests are one per window per command:
each focus change scrolls the strip, so every window gets a new target; no repeated
targets were sent. Memory and idle cost stay flat up to 51 windows; no crash report.

## Code inspection (not executed)

- **Focus history** (`748410d3`, `e76ef93b`): weak window identities, so a recycled
  WindowServer ID cannot inherit history; fallback runs only if the closed window was
  the requested focus; `setFocus` changes logical focus only and refuses a workspace
  that is not showing — it cannot activate an app or switch Spaces.
- **Wide-column swipe assist** (`43c24957`): advances at most one adjacent column,
  never reverses, stops at strip ends, and only on a *committed* Dock swipe; a
  cancelled swipe takes `cancel()` (no focus, no assist). Space changes cancel the
  gesture. Finger-following and Option+two-finger code paths unchanged.
- **Drag preview** (`4961f1c1`, `3d2f14c1`): hidden on mouse-up, on any Space/window
  invalidation and after 3 s without drag events; panels are app windows and go with
  the process.

## Issues

**P0:** none. **P1:** none.

**P2**
- After an app's last window closes, StripMuxX's logical focus can name another app's
  window while macOS keeps the windowless app frontmost, until the next native focus
  change.
- Focus latency 90–150 ms median (60–90 ms of main-process CPU per command), growing
  about 1 ms per window; dominated by AX work, not redundant writes.
- Earlier P2 items stand: outer-column widths, Option-letter shortcut shadowing
  (an opt-in ergonomic preset now exists), dropped `Task` errors, 29 warnings.

## Not executed physically

Three-finger swipes at 33/50/100/150/200% widths, flicks, cancellation, 50-column
swipes and Space switches mid-gesture (no synthetic Dock gestures); Option+two-finger
pan; Mission Control; switching and moving across desktops (one desktop); two
displays and disconnect; sleep/wake; restart and layout restoration (restart not
permitted); VoiceOver, Reduce Motion, keyboard-only Settings; installer rollback.

---

# Gesture and persistence audit — 2026-11-15

Tested at `471410c5` plus the two fixes below (installed as build 44). Baseline
`make check`: 533 XCTest, 59 Python, 0 failures, 26 warnings. After the fixes:
**536 XCTest, 59 Python, 0 failures.**

## Fixes

| Defect | Evidence | Fix |
| --- | --- | --- |
| Momentum after an Option+Shift resize scrolled the app under the pointer sideways | Regression test: 5 of 5 momentum events leaked | `fb185d71`: swallow the resize's momentum until it ends |
| A strip change made within 350 ms of quit or `enable off` was lost | Regression test: saved offset 0 instead of 280 | `6f30df73`: flush the pending save before tiling stops |

## Automated (executed)

- `testFiveThousandRandomScrollEventsKeepEveryInvariant`: seeded random phases,
  momentum, missing lift events, modifier changes, reversals, zero and vertical
  deltas. After every event: an idle plain scroll is never consumed; focus never moves
  during a resize; the placed viewport stays in range; widths stay within the display;
  another desktop is never touched. Passes.
- Persistence: invalidated pending saves are written at the next accepted observation;
  same-app pairing, late or missing windows and the 90 s grace period have existing tests.

## Physical (executed on this Mac, synthetic CGEvents to a disposable fixture app)

| Check | Result |
| --- | --- |
| Plain horizontal scroll reaches the app | 7/7 |
| Option pan consumed, strip moves | 0/12 reached the app; strip moved 440 pt |
| Option + vertical scroll reaches the app | 7/7 |
| Option+Shift resize, lift, momentum (3 runs) | 0/15 reached the app each run; width +120 pt per run (momentum never resized); focus unchanged |
| Plain scroll after a resize | 5/5 |

**P2:** if the fingers rest more than 250 ms mid-resize, the idle timer ends the
gesture and the zero-delta lift event reaches the app. No momentum follows a still
lift, so nothing scrolls; closing it would mean changing the idle timer.

## Not executed

Three-finger Dock swipes (no reliable synthesis), quit and `enable off` on the live
desktop (would move work windows; covered by the regression test), multiple desktops
and displays (one of each), Atlas VM runs.

---

# Features and borders pass — 2026-11-15 (evening)

Tested at `ffc7cca1` (installed as build 74) on one built-in display, one desktop.
`make check`: **571 XCTest, 59 Python, 0 failures.** CI green on every push since
`1b22c573`; the two earlier failures were commits pushed without `make check`
(`AGENTS.md` now forbids that).

## Shipped since the gesture audit

Floating windows stay floating and are findable (minimap row, `focus floating`);
the auto-join experiment was reverted. Minimap redesign and compact sizing.
`shortcuts` cheat sheet. Per-app column width in `on-window-detected`
(`scrolling-width <share>`, `scrolling-width-pixels`). Finder managed (no AppKit
launch date). Commit hash linked into the binaries. WinMuxX borders port (another
session) with the fixes below.

## Fixes found in this pass

| Defect | Evidence | Fix |
| --- | --- | --- |
| Borders trailed a panning window by up to 100 pt and stayed 33 pt off at the strip end | WindowServer frames sampled every 15–30 ms during synthetic pans | `6f2454ba`: follow real frames every display frame from the first scroll step |
| Every border blinked after each pan | Border missing in 3–4 samples per pan; doctor: every read hid them as a "desktop change" | `16a054ac`: compare with the desktops last seen; ignore reads without a snapshot |
| `focus floating` returned to the strip's most recent window, not the one it left | From Safari it came back to ZapFast | `ffc7cca1`: remember the strip window it left |

WindowServer move notifications (806) were tried for the borders and measured no
better than per-frame following; removed. A following border trails by one display
frame, so `borders.hide-while-scrolling` (off by default) hides them during a gesture.

## Physical (executed on this Mac)

| Check | Result |
| --- | --- |
| Option pan, borders following (4 pans, 2 speeds) | 0 missing samples; trailing one display frame (20–40 ms) |
| Option pan, `hide-while-scrolling = true` | Hidden from the first step; back once, about 150 ms after the strip stops |
| `focus left/right`, `scrolling-focus first/last` | Border exact or one sample late; one 20 ms gap as focus moves across the strip |
| Floating fixture window | Listed in the minimap's floating row ("5 columns · 1 floating") |
| `focus floating` from Safari, twice | Floating window, then Safari |
| Minimap | 48 pt row, compact tiles, panel sized to the strip |
| Cheat sheet | Your bindings in Focus / Move / Columns / Desktops, three columns |
| Installs 61–74 | Installer validated window assignments after each restart, except where focus changed during validation |

## Not executed

- `focus floating` from other windows: results were inconsistent because focus was
  changing during the run (the Mac was in use); re-test with the Mac idle.
- Per-app width rules with a real app (needs a rule in your config).
- Three-finger Dock swipes cannot be synthesised. **User test (trackpad, borders
  shown):** "almost good" — the border starts partly behind the window on the
  leading side and trails slightly during the scroll; not a major issue. This is the
  one-frame follow lag; `hide-while-scrolling` covers only the Option + two-finger pan,
  not the Dock swipe path. P3.
- Desktop switches with borders (not permitted), multiple displays, restart
  restoration of floating windows after the other session's persistence changes.

---

# Improvement round — 2026-11-16

Installed as build 77; `make check`: **573 XCTest, 59 Python, 0 failures, 0 compiler
warnings in the product code** (was 17; four test warnings remain for an accessibility
call with no replacement).

## Previously unexecuted paths, now executed (disposable fixture app)

| Check | Result |
| --- | --- |
| `focus floating` from two different strip windows | Floating window, then back to the starting window, both times |
| Floating window across a StripMuxX restart | Still floating, same desktop, 0 saved layouts pending |
| `on-window-detected` + `scrolling-width-pixels 700` with a real app window | Window opened 700 pt wide; config restored byte-for-byte |

## Improvements

| Change | Evidence |
| --- | --- |
| Commands no longer force a full SkyLight + AX reread when the model is already current | `focus` left/right p50 81 → 48 ms, p90 148 → 65 ms (including a 25 ms CLI round trip); 3 presses 50 ms apart still land on the right column; 0 failures in 30 runs |
| The lift of a resize the idle timer ended no longer reaches the app | 0 of 3 runs leaked events after a 450 ms rest; a plain scroll afterwards still reaches the app; unit tests for both touch outcomes |
| Thrown errors in shortcut, menu-bar reload and app-startup tasks are logged instead of dropped | startup failures also show a message |
| 17 compiler warnings cleared | `swift build` from a full rebuild: none |

## Polish round (builds 78–79)

| Finding | Evidence | Fix |
| --- | --- | --- |
| Cheat sheet kept 13 MB and the minimap 4 MB after closing | `footprint`: fresh 24 MB → 38 MB after one cheat sheet, never returned | Cheat sheet frees its panel on close; the minimap frees its panel 6 s after closing. 38 → 26 MB, 28 → 25 MB |
| A held key skipped about half its repeats | 25 `focus right` at 33 ms: 13 refused with "target changed during reconciliation" | Pure navigation (focus, scrolling-focus, scrolling-center) follows the current focus; edits and closes keep the strict fence. 25/25 accepted both directions |
| Stale planning docs | 9 broken links, a "WinStrip on SpaceMux" plan, three "missing" features that exist | `docs/architecture` removed; the accurate events note is `docs/STATE_AND_EVENTS.md`. No broken links in any markdown file |

Stress (20 fixture windows, 120 random commands, 6 pans each way, three rounds): no
crash, tiling stayed active, borders and columns returned to their idle counts,
footprint plateaued at about 38 MB from round 1 (no growth in rounds 2 and 3). A
hidden SwiftUI Settings window accounts for about 12 MB of the 24 MB baseline; removing
it needs macOS 15 as the minimum, so it stays. The CLI's local socket logs harmless
`nw_path_evaluator` errors from Network.framework on every command.

## Plan items done alone (builds 80–82)

| Item | Evidence |
| --- | --- |
| Gesture writes no longer grow with the number of windows | One 30-step pan with 3 / 13 / 28 / 48 columns: 72 / 390 / 616 / 1008 writes before, 42 / 87 / 102 / 107 after. Apps apply a gesture write in 3.4 ms on average (`doctor`). All 27–29 layout passes per 31 input events still run |
| Overlays are tested by what they draw | `OverlayRenderingTest`: tiles drawn, focused edge clearly more accent, compact tiles, header/footer/chips, cheat-sheet columns. Blanking the tile drawing fails 5 assertions |
| Settings search reaches every border option | 7 controls added; "border", "colour", "trail" all find them |
| CHANGELOG, command docs and install/rollback/uninstall docs | `focus-back-and-forth` documented; installer statuses explained in `docs/FORK.md` |
| Real gestures can be measured | `debug-windows --gesture-trace-start/stop` + `script/analyze_gesture_trace.py` (see `docs/TESTING.md`) |

Not conclusive: pan latency in milliseconds. The live desktop moved under the test (the
terminal running it was itself parked off-screen by the strip), so timings were
unreliable; the built-in `doctor --simulate-native-pan` probe no longer pans (its
self-posted events are ignored) and was left alone.

The earlier P2 "lift after an idle-settled resize" is closed. Three-finger swipes with
`borders.hide-while-scrolling`: by code path they share the Option pan's `pan` call and
hide the same way; still not exercisable by synthetic events (user trackpad test with the
setting off: "almost good").
