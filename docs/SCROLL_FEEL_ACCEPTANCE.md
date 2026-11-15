# Scroll feel / free-size beta acceptance matrix

Status: planned tests. **No row below is a claim of execution.** Record results
in `docs/QA_AUDIT.md` only after running them.

## Automated tests to implement

| ID | Setup / action | Invariant |
| --- | --- | --- |
| S01 | Tiny horizontal deltas across consecutive Option pan events | Fractional movement accumulates; correct sign; no jumps |
| S02 | Reverse direction in active gesture | Immediate reversal; no leftover directional acceleration |
| S03 | Native momentum start/change/end | Bounded offset, no duplicate application, no leaked events |
| S04 | Missing lift, cancellation, Space change | Gesture state safely reset; no focus or unrelated Space mutation |
| S05 | Pan with focused window outside viewport | Focus identity stable; camera moves only |
| S06 | Keyboard focus on partly visible column | Minimal reveal/centering according to existing preference |
| S07 | Resize during camera offset and pinned column | Anchor stable; pinned frame unchanged |
| S08 | Option+Shift resize then momentum | No momentum scroll or further resize; plain scroll works afterward |
| F01 | Convert tiled -> free-size | Preserves pre-conversion size and vertical position |
| F02 | Scroll mixed tiled/free-size columns | Free-size width/height unchanged; strip order preserved |
| F03 | User manually resizes free-size window | Subsequent pan and restore retain new dimensions |
| F04 | Free-size -> tiled -> free-size | Restores saved free-size dimensions when valid |
| F05 | Restore old persistence snapshot | Defaults to existing tiled/floating behavior |
| F06 | Save/restore new snapshot with missing windows | Saved free-size mode and geometry survive grace-period recovery |
| F07 | Display size or resolution changes | Geometry clamped safely; saved preferred dimensions not destroyed |
| F08 | Reorder, close, move desktop, pin/unpin | No orphaned metadata or incorrect focus |
| F09 | Modal / utility floating window | Remains independent of strip by default |
| F10 | AX frame write rejection | No write loop; logical layout remains coherent |

Extend existing test fixtures instead of relying on sleeps or global accessibility
permissions for deterministic geometry tests. Mutation-check newly added regression
assertions, as in `docs/QA_AUDIT.md`.

## Physical trackpad matrix (user Mac)

Perform on a disposable native Space; do not rearrange active work windows.

| ID | Configuration | Action / expected behavior |
| --- | --- | --- |
| P01 | 33% columns | Slow Option pan: direct, stable; lift stops |
| P02 | 50% columns | Fast Option flick: natural bounded momentum |
| P03 | 100% columns | Three-finger swipe reaches neighboring column |
| P04 | 150%, 200%, fixed oversized | Wide-column assist; no skip/cancel activation |
| P05 | Any width | Reverse mid-gesture, then stop; no delayed movement |
| P06 | Option+Shift resize | Resize only; no momentum leak; focus stable |
| P07 | Mixed free-size/tiled | Scroll/focus/reorder without size changes |
| P08 | Free-size window | Resize manually, switch Space, return; frame retained |
| P09 | Free-size window | Quit/restart and restore; compare exact frames |
| P10 | Two displays | Move between displays, disconnect/reconnect; no offscreen loop |
| P11 | Native Space switch during gesture | Correct cancellation, no other desktop touched |
| P12 | Reduce Motion / Mission Control | No unintended animation, activation or persistence loss |

For physical failures capture: build number, SHA, display scale, active
column widths, event type and direction, observed vs expected viewport,
`stripmuxx doctor` counters and a minimal reproduction.

## Performance gate

Compare baseline and candidate with 5, 20 and 50 windows: p50/p90 input-to-frame
latency, CLI focus latency, CPU time per command, AX frame requests, idle
wakeups, RSS and redundant frame targets. No regression should be declared
acceptable without documenting why. Measure direct pan separately from
keyboard-driven scrolling; a CLI focus measurement is not input-to-photon latency.

## Required reporting

For each commit: SHA, changed behavior, associated test IDs and result.
For the final branch: exact `make check` counts and failures, current warnings,
physical tests passed/failed/not executed, and known P1/P2 risks. Never
describe a synthetic Dock gesture as real-trackpad validation.
