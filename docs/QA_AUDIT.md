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
