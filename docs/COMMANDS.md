# Command guide

Run `stripmuxx --help` for the command list and `stripmuxx <command> --help` for
arguments. This guide groups commands by what they affect. A WinMux command
StripMuxX does not support (such as `workspace-layout` or `summon-workspace`) is
recognized in configuration and skipped; `doctor` lists it.

**Focused window:** `focus`, `move`, `resize`, `swap`, `join-with`, `layout`,
`fullscreen`, `close`, `close-all-windows-but-current`, `macos-native-fullscreen`
and `macos-native-minimize`. These use the focused window unless a command's help
documents an explicit target such as `--window-id`.

**The strip:** `scrolling-pan left|right|focus` moves the viewport without switching
window focus; left/right pan by half a viewport, focus reveals the active column.
`scrolling-width-pixels N` sets a fixed column width in points (persisted across
restarts and changes of display size). `scrolling-width next|previous|full` changes the focused column's
width; `scrolling-center` centers it. `scrolling-focus 1-9|first|last` focuses a
column by place (9 is the last), `scrolling-move 1-9|first|last` moves the focused
column there, and `scrolling-pin left|right` pins it to an edge of the display (again
to unpin). `scrolling-minimap` opens or closes the clickable map of the strip; it
supports Left/Right, Return and Escape. `balance-sizes` resets column widths and
stack heights; `flatten-workspace-tree` turns stacks into columns. See
[the strip](LAYOUTS.md).

**Undo:** `undo-layout` puts the focused desktop's strip back as it was before its
last layout command (`layout`, `move`, `join-with`, `resize`, `balance-sizes`,
scrolling moves, widths and pins, and similar), one step at a time, up to 20 steps.

**Retile:** `retile` puts every tiled window on the showing desktops back in its
place and reports how many had moved. An app that moves its tiled window again and
again is put back at most three times in 10 seconds per place, then left alone until
that time passes or the layout changes; `retile` renews that budget.

**Desktops:** `workspace 1-9|next|prev` switches the focused display's desktop, as
Control-N does; `workspace-back-and-forth` returns to the previous one.
`move-node-to-workspace` moves the focused window to another desktop, optionally
following it with `--focus-follows-window`. Desktops are numbered in Mission Control
order.

**Displays:** `focus-monitor` and `move-node-to-monitor` act on displays.
`move-workspace-to-monitor` moves a desktop's windows and strip to the desktop the
other display shows; macOS keeps the desktop itself where it is.

**Experimental input diagnostics:** `debug-windows --gesture-probe-start` starts an opt-in,
non-intercepting public-API gesture probe. With another app focused, try a horizontal
scroll using two fingers, three-finger swipe and four-finger Space switch, then run
`debug-windows --gesture-probe-stop` for aggregate counts. The probe does not
record content or finger locations and **cannot identify finger count**; it tests
whether public event streams are observable before any gesture engine is selected.

**Inspect and maintain:** `list-workspaces`, `list-windows`, `list-apps`,
`list-modes`, `list-monitors`, `list-exec-env-vars`, `config`, `doctor`,
`reload-config` and `enable` provide queries, diagnostics or runtime controls.

**Automation:** `exec-and-forget`, `trigger-binding`, `mode` and `move-mouse` are
used by configured workflows. `debug-windows` records Accessibility debugging
information; review its output before sharing it.

Use `stripmuxx --help` as the live command inventory because options can change
between releases.
