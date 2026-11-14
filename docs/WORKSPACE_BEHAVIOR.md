# Desktop and strip behavior examples

These describe current behavior, not a ban on an explicitly requested change.
A workspace is a macOS desktop (a Space in Mission Control); each one holds one
horizontal strip of columns. M is the main display and S a secondary display.
Desktops are numbered in Mission Control order, as Control-1 … Control-9 count them.

## Desktops and displays

| Before and action | Expected result | Existing evidence |
| --- | --- | --- |
| `workspace 2` | macOS switches to desktop 2; the command succeeds only once a fresh read confirms the landing | `testSwitchSucceedsOnlyAfterTopologyConfirmsTheLanding` |
| Several `workspace next` in quick succession | Each counts from the switch in flight, not from a stale desktop | `testNextCountsFromTheSwitchInFlight`, `testABurstRetargetsTheSwitchInFlightInsteadOfSwipingFromAStaleSpace` |
| Desktop 2 shows on S; `workspace 2` from M | S keeps desktop 2 and it receives focus there; nothing moves between displays | `testWorkspaceNShowingOnTheOtherDisplayFocusesItThere` |
| `workspace-back-and-forth` | The focused display's previous desktop; fullscreen Spaces are skipped | `testBackAndForthReturnsToTheDisplaysPreviousDesktop`, `testHooksFireOnceWithDesktopNumbersAndHistorySkipsFullscreen` |
| A switch to another display's desktop | Strips on every other display are untouched | `testSwitchOnOneDisplayPreservesOtherDisplaysAndTrees` |
| Desktops are reordered in Mission Control | Each strip stays with its desktop (by UUID), not with its number | `testRenumberedSpaceKeepsUUIDLayoutAndRemovedSpaceIsRetainedWithoutVisibility` |
| `move-node-to-workspace 3` | The window moves to desktop 3 once macOS confirms it, and joins that desktop's strip; an unconfirmed move leaves both strips as they were | `testConfirmedMoveRehomesTheWindowIntoTheDestinationLayout`, `testUnconfirmedMoveIsReportedAndLeavesTheTree` |
| `move-node-to-monitor` | The window joins the desktop the other display shows | `testMoveNodeToMonitorJoinsTheDesktopThatDisplayShows` |
| `move-workspace-to-monitor` | macOS cannot move a desktop between displays, so its windows join the other display's desktop: into an empty desktop the strip arrives whole, otherwise its columns are appended | `testMoveWorkspaceToMonitorCarriesTheStripIntoTheOtherDisplaysDesktop` |
| `focus right` / `move right` at the strip's end with `--boundaries all-monitors-outer-frame` | Focus or the window continues onto the next display | `testDirectionalFocusAndMoveCrossToTheNextDisplay` |
| `persistent-workspaces = ['1', … '5']` with three desktops | Desktops 4 and 5 are added, one per confirmed read, on the display `workspace-to-monitor-force-assignment` names, else the main one; none is ever removed | `testCreatesOneDesktopPerConfirmedReadAfterTheDisplaysSettle`, `NativeDesktopTopUpTest` |
| A fullscreen app's Space is showing | It has no strip and none is created; StripMuxX leaves it to macOS | `testNoGuessedDisplayOrUUIDAndFullscreenIsUnmanaged`, `testADisplayShowingAFullscreenSpaceHasNoDesktopAndCreatesNone` |

## The strip

| Before and action | Expected result | Existing evidence |
| --- | --- | --- |
| Columns A B C, focus A; `move right` | B A C; at the strip's end nothing happens unless `--boundaries-action fail` | `testMoveCarriesTheColumnAlongTheStrip` |
| Focus A; `join-with right` | A stacks on top of B in B's column, which keeps its width | `testJoinStacksAndMoveOutRestoresAColumn` |
| A stacked window; `move left` | It leaves the stack for a column of its own; a stack of one becomes a plain column | `testJoinStacksAndMoveOutRestoresAColumn` |
| `focus right` into a stack | The stack's most recently used window | `testFocusCrossesColumnsAndWalksAStack` |
| `layout floating` on a stacked window | It floats above the strip; the stack left behind collapses | `testFloatingLeavesTheStripAndTilingReturnsToIt` |
| `flatten-workspace-tree` | Every stack becomes columns, in order | `testFlattenTurnsEveryStackIntoColumns` |
| `scrolling-focus 3`, `scrolling-move first` | Focus or move by place on the strip; 9 is the last column | `testFocusAndMoveByPlaceOnTheStrip` |
| Switching away from a desktop and back | Its columns, stacks and floating windows are as they were | `testSpaceSwitchRetainsIndependentStacksAndFloatingWindows` |
| StripMuxX restarts | Each desktop's strip is restored once all its windows are matched; until then the saved strip is protected from autosave | `testNativePersistenceRoundTripProtectsIncompleteSavedTreeFromAutosave`, `testAMissingWindowIsDroppedFromTheRestoredTreeOnlyWhenPartialIsAllowed` |

Desktop navigation and cross-desktop moves live in
`Sources/AppBundle/runtime/NativeSpaceNavigator.swift` and
`Sources/AppBundle/runtime/NativeWindowSpaceMoves.swift`; strip edits in
`Sources/AppBundle/tree/StripEdits.swift` and the commands in
`Sources/AppBundle/command/impl`.

## Preservation and desktop checks

Keep each desktop's column order, stacks, column widths, pinned column and floating
windows. Pixel coordinates can change to fit the display's usable area and
applications' minimum sizes.

On the desktop, switch between populated desktops with Control-arrow and the
trackpad, move windows between desktops and displays, and restart StripMuxX.
Mission Control reordering, fullscreen apps and display disconnects need real checks:
model tests do not establish native Accessibility behavior or how macOS places Spaces.
