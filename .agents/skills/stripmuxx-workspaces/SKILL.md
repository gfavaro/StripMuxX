---
name: stripmuxx-workspaces
description: Implement or review StripMuxX desktop navigation, moves between desktops and displays, and each desktop's scrolling strip. Use for changes to workspace commands, native Space observation, strip edits or layout persistence.
---

# Desktop and strip changes

Read [core principles](../../../docs/PRINCIPLES.md) and the architecture section in
[HACKING](../../../HACKING.md). Resolve these paths from this skill directory.

A workspace is a macOS desktop. macOS owns which desktops exist, their order and
which one each display shows; StripMuxX observes that and keeps one strip per
desktop, keyed by the desktop's UUID. Distinguish the three kinds of change:

- **Navigation** (`workspace`, `workspace-back-and-forth`, `focus-monitor`) asks macOS
  to switch and waits for a fresh read to confirm it. It never edits a strip.
  Start in `Sources/AppBundle/runtime/NativeSpaceNavigator.swift`.
- **Moves between desktops or displays** (`move-node-to-workspace`, `move-node-to-monitor`,
  `move-workspace-to-monitor`) move windows by ID and change a tree only after macOS
  confirms each arrival. Start in `Sources/AppBundle/runtime/NativeWindowSpaceMoves.swift`.
- **Strip edits** (`move`, `join-with`, `resize`, `layout`, `scrolling-*`) change the
  showing desktop's tree inside the tiling fence. Start in the command under
  `Sources/AppBundle/command/impl` and `Sources/AppBundle/tree/StripEdits.swift`.

## Current behavior and entry points

Read [behavior examples](../../../docs/WORKSPACE_BEHAVIOR.md) for concrete
navigation, move, strip and restart cases. These describe today's behavior, not a
prohibition on an explicitly requested change. The
[task map](../../../docs/CONTRIBUTOR_TASKS.md) identifies entry points, completion
criteria and how to handle failures.

## Implementation and verification

Keep the strip's shape: the root's children are columns, a column is a window or a
vertical stack of at least two windows, stacks never nest, and floating windows are
children of the workspace itself. `Workspace.normalizeContainers()` restores that
shape after an edit; call it rather than repairing the tree by hand.

Strips belong to a desktop's UUID, not its number: Mission Control can renumber
desktops at any time. Never guess a display or a desktop when an observation is
missing; a command whose target changed during reconciliation is refused.

Use the existing tests as starting points:

- `Sources/AppBundleTests/command/StripCommandsTest.swift`
- `Sources/AppBundleTests/runtime/NativeSpaceNavigatorTest.swift`
- `Sources/AppBundleTests/runtime/NativeWindowSpaceMovesTest.swift`
- `Sources/AppBundleTests/runtime/NativeSpaceLayoutsTest.swift`
- `Sources/AppBundleTests/runtime/NativeTilingTest.swift`

`setUpWorkspacesForTests(desktops:)` in `Sources/AppBundleTests/testUtil.swift`
publishes an observation of numbered desktops and marks tiling ready; `TestWindow.new`
registers each window's membership. Follow [Testing](../../../docs/TESTING.md) for
serial suite execution.

```sh
swift test --no-parallel --filter StripCommandsTest
swift test --no-parallel --filter NativeWindowSpaceMovesTest
swift test --no-parallel --filter NativeSpaceLayoutsTest
```

Run the subset relevant to the change, then the required `make check` gate. Confirm
the filter executed tests. If piping output, preserve the test command's exit status
with `pipefail`; a successful `tail` or `tee` does not establish test success.

When checking preservation, inspect the live workspace root and its reachable
children after the operation; captured references to an old tree can remain intact
even if the workspace now uses another one. Assert column order, stack membership,
column widths and floating parentage, on both desktops for a move. A failing test is
a reason to compare expectations with the requested behavior before changing
production code.

Report manual checks separately from automated results. Real validation switches
between populated desktops, moves windows between desktops and displays, reorders
desktops in Mission Control and restarts StripMuxX. Do not imply installation from a
build.
