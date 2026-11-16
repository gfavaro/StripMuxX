# Recipes

Examples use StripMuxX's TOML names and commands. Back up your config before editing;
Settings → Configuration validates before applying changes.

## Keep one window a comfortable shape on an ultrawide

In Settings → Windows choose the lone-window aspect ratio and alignment, or set:

```toml
single-window-aspect-ratio = 1.4
single-window-alignment = 'center'
```

Set the ratio to `0` to let a lone window fill the display again. See the
[full explanation](../README.md#lone-windows).

## Follow Scene's theme

[Scene](https://github.com/gfavaro/Scene) can set StripMuxX's accent whenever it applies a theme.
The accent colors the focused border (while `borders.active-color` is `'accent'`, the default),
the minimap's focused tile and viewport, and the shortcut cheat sheet.

The script ships inside the app, so it always matches the installed build. In Scene → Settings →
Scripts add:

```
/Applications/StripMuxX.app/Contents/Resources/scene-stripmuxx.sh
```

On each theme Scene runs it with `SCENE_ACCENT`; it sets the root `accent-color` in `~/.config/stripmuxx/stripmuxx.toml` and
reloads the config. The first time, it records your own `accent-color` (or that you had none), and
Scene's Restore puts that back. It changes nothing else in the file. Set `STRIPMUXX_CONFIG` or
`STRIPMUXX_CLI` to use other paths.

## Two columns per screen, or three

```toml
[scrolling]
column-width = 0.3333
width-presets = [0.3333, 0.5, 0.6667, 1.0]
center-focused-column = 'on-overflow'
```

New columns take a third of the display; `scrolling-width next` (Alt-R) steps
through the presets. `on-overflow` centers the focused column only when the strip is
wider than the display.

## Float an app's windows

```toml
[[on-window-detected]]
if.app-id = 'com.apple.systempreferences'
run = 'layout floating'
```

Settings › Automation › Rules writes the same rule. Remove the table to tile the app again.

## Open an app at a set width

```toml
[[on-window-detected]]
if.app-id = 'com.apple.Safari'
run = 'scrolling-width 0.66'      # a share of the display, 0.1 to 1

[[on-window-detected]]
if.app-id = 'com.mitchellh.ghostty'
run = 'scrolling-width-pixels 900' # or a width in points
```

The width applies to the new window's own column only, whatever is focused. A window
that opens floating or in a stack keeps its size. `scrolling-width 0.5` also works as a
binding, for the focused column.

## Use one side of a modifier

```toml
[modifiers]
alt = 'left'
```

This lets right Option type characters while StripMuxX bindings use left Option.
Values are `both`, `left` and `right`. Remove the setting to use both sides.

## Send an app to a space only when it launches

```toml
[[on-window-detected]]
if.app-id = 'net.imput.helium'
if.app-has-other-windows = false
run = 'move-node-to-workspace 5'
```

The rule moves only the window an app opens when it launches, while StripMuxX manages
no other window of it. Windows the app opens later, such as login or dialog windows,
open on the current space, next to the app, instead of following the rule.
Settings › Automation › Rules offers this as **App windows › Only the app's first window**.

