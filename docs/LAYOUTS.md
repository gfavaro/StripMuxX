# The strip

StripMuxX has one layout: each desktop is a horizontal strip of columns, as in
[niri](https://github.com/YaLTeR/niri) or PaperWM. There are no splits, tabs or
other layouts.

## Columns

A new window becomes a column to the right of the focused one, `[scrolling]
column-width` wide (a share of the display, gaps included: 0.49 shows two). When the
columns are wider than the display, the strip scrolls: focusing a column brings it
into view, and `[scrolling] center-focused-column` chooses whether it also centers
(`never`, `on-overflow` or `always`). Option with a two-finger horizontal trackpad
scroll pans the strip by hand.

`scrolling-width next|previous` steps a column through `[scrolling] width-presets`,
`scrolling-width full` fills the display, and `resize width ±N` changes it in points.
`scrolling-center` centers the focused column. `scrolling-pin left|right` pins it to
an edge of the display while the rest of the strip scrolls beside it; run it again to
unpin. `balance-sizes` gives every column the configured width again.

`focus left|right` moves between columns and `move left|right` carries the focused
column along the strip. `scrolling-focus 1-9|first|last` and `scrolling-move …` go by
place, 9 being the last column, like browser tabs. The minimap (`scrolling-minimap`)
shows the whole strip; click or drag a column there to focus or reorder it.

## Stacks

`join-with left|right` puts the focused window into the column on that side, stacked
with its windows; joining to the right puts it on top. The stack keeps that column's
width. `focus up|down` and `move up|down` work within the stack, `resize height ±N`
shares its height differently, and `move left|right` takes a window out into a column
of its own. A stack of one window is just a column again. `flatten-workspace-tree`
turns every stack on the desktop into columns.

## Floating and fullscreen

`layout floating` lifts the focused window off the strip and `layout tiling` puts it
back; `layout floating tiling` toggles. `layout floating --for-next-detected-window`
floats only the next window that opens. Window rules (`on-window-detected`) can float
windows by app or title. `fullscreen` widens a window over the desktop without
leaving the strip; `macos-native-fullscreen` gives it a macOS fullscreen Space.

## Lone ultrawide window

On ultrawide displays, a lone tiled window can use a configurable maximum width
(`fullscreen-width`) and alignment (`single-window-alignment`), per display with
`[display.<pattern>]` tables. The [ultrawide diagram](assets/layouts/ultrawide.svg)
illustrates this behavior.

## Undo

`undo-layout` puts the desktop's strip back as it was before its last layout command,
one step at a time, up to 20 steps. It rearranges only windows still on that desktop.
