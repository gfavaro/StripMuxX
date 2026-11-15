# StripMuxX QA, regression and stability audit — 2026-11-14

**Verdict: PASS WITH WARNINGS.** `make check` passes (507 XCTest cases, 53 Python
checks). Six defects were fixed; one P1 and several P2 risks remain, and the physical
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
`faa85330` … `72576197` (see [§5](#5-bugs-found-and-fixed)).

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
| Final `make check` | **507 run, 0 failures** | 53 run, 0 failures | **PASS** |

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

Not measured: 15/30/50 windows, two displays, sustained interaction. Those need
disposable fixture windows on a test desktop (§7).

Frame-write pipeline (reviewed, verified in code): one AX thread per app, one pending
write per window (latest wins), writes cancelled on invalidation, permits checked per
write. Dinky's `FrameScheduler`/`FrameApplier` were not re-compared in this pass; no
change to the pipeline is proposed without a measured gap.

## 7. Not executed

| Area | Why |
| --- | --- |
| 15–50 real windows, two displays, display disconnect, sleep/wake | Would rearrange your live desktop; needs a dedicated test desktop and your go-ahead |
| Space switching, moving windows across Spaces and displays, app quit/relaunch, StripMuxX restart | Same; automated simulations of these pass (`NativeSpaceNavigatorTest`, `NativeWindowSpaceMovesTest`, `NativeTilingTest`) |
| Three-finger gesture, Mission Control interplay | No synthetic Dock gestures without permission; you validated the gesture manually; code unchanged |
| VoiceOver, Reduce Motion, keyboard-only Settings walk-through | Manual UI checks |
| Settings persistence across an app update | Requires installing over a customised config; the save path is covered by `SettingsPersistenceRegressionTest` |

## 8. Remaining risks

**P0:** none found.

**P1**
- **Edge preview below 40 pt is not honoured.** macOS keeps about 40 pt of a window on
  its display. With `edge-preview = 0` (your config) or the default 14, parked windows
  are shown 40 pt wide at the right edge, and the desired frame never matches the real
  one. Put-back no longer fights it (fix 3), but the setting promises something macOS
  will not do. Decide: clamp the effective preview to 40 pt, or document it.
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

## 9. Recommended next actions

1. Decide the edge-preview floor (P1) and align the Settings range.
2. Run the §7 physical matrix on a test desktop with `script/native-spaces-fixture.swift`.
3. Relax the installer's Screen Recording requirement.
4. Offer an opt-in shortcut preset that avoids Option-letter keys (for example
   `modifiers.alt = 'left'` plus Ctrl-Option chords), without changing existing bindings.
5. Run `make check` before every push.
