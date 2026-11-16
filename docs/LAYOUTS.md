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
scroll pans the strip by hand. `scrolling-pan left|right` moves the viewport by
half its visible width without changing keyboard focus; `scrolling-pan focus`
reveals the focused column. Default shortcuts: Option-Control-H/L and
Option-Control-C, respectively.

`scrolling-width-pixels N` sets a column to a persistent width of N macOS points,
independent of display size. Relative width presets reset this absolute-width mode.
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

## Free-size columns

`layout free-size` adds the focused window as a **free-size strip column**.
Its width, height and vertical placement remain user-controlled while its
horizontal position follows the strip. A floating window can join the strip in
this mode without being stretched to the full tile height. If the selected
window is in a vertical stack, it first becomes a separate column.

`layout tiling` returns a free-size window to normal tiled sizing;
`layout floating` removes it from the strip and preserves its preferred
dimensions. This mode is opt-in: existing floating rules are unchanged.

Free-size geometry is included in the native Space restoration snapshot.
The implementation has **not been compiled or physically validated** in this
series of commits. See [implementation status](SCROLL_FEEL_IMPLEMENTATION_STATUS.md).

## Window borders

The WinMuxX border engine is restored: native eight-piece WindowServer borders,
continuous rounded vector paths, backing-pixel alignment at 1× and Retina scale,
native WindowServer order matching, and the original click-through AppKit fallback.
Borders follow visible, managed windows as the strip moves and across native
Spaces. Native Space transitions and Mission Control hide stale overlays.
Dialogs and non-document utility surfaces are excluded using the original
WinMuxX document-window filter; floating windows continue floating.

The original WinMuxX options are supported in the TOML config and in
**Settings → Appearance → Window borders**:

```toml
# Optional. Leave unset to follow the system accent color.
# accent-color = '#5E9EFF'

[borders]
enabled = true
width = 4
active-color = 'accent'
inactive-color = '#00000000'
order = 'below'
exclude-apps = []
```

Colors accept `accent`, `#RRGGBB`, or `#RRGGBBAA`; widths may be fractional.
The minimap's focused tiles, viewport outline, and insertion indicators and
the shortcut cheat sheet's headings/key badges share the **same resolved
active border color**. Set `active-color = 'accent'` to use the optional root
`accent-color` (or the system accent when omitted). Changes are applied when
configuration reloads, including when these overlays are already visible.
When the native renderer cannot operate on the current macOS version, the
same original WinMuxX fallback panels render the same vector border geometry.
Unlike WinMuxX, StripMuxX has no tab-bar or virtual-workspace chrome to surround.
The native engine and its rendering tests are copied from WinMuxX; the native
Space lifecycle adapter is specific to StripMuxX.

**Verification status:** source-only port; no macOS compilation, hardware test,
or `make check` was run in this commit series. Physically verify fullscreen,
Mission Control, Space switches, external displays, fractional widths, dragging,
and the native-to-fallback transition before considering this release-ready.

## Floating and fullscreen

`layout floating` lifts the focused window off the strip and `layout tiling` puts it
back; `layout floating tiling` toggles. `layout floating --for-next-detected-window`
floats only the next window that opens. Window rules (`on-window-detected`) can float
windows by app or title. Floating windows stay on their desktop: the minimap lists
them under the strip (click one to focus it), and `focus floating` (Alt-Shift-V)
focuses each in turn, then returns to the strip. `fullscreen` widens a window over the desktop without
leaving the strip; `macos-native-fullscreen` gives it a macOS fullscreen Space.

## Lone ultrawide window

On ultrawide displays, a lone tiled window can use a configurable maximum width
(`fullscreen-width`) and alignment (`single-window-alignment`), per display with
`[display.<pattern>]` tables. The [ultrawide diagram](assets/layouts/ultrawide.svg)
illustrates this behavior.

## Undo

`undo-layout` puts the desktop's strip back as it was before its last layout command,
one step at a time, up to 20 steps. It rearranges only windows still on that desktop.
