# Recipes

Examples use StripMuxX's TOML names and commands. Back up your config before editing;
Settings → Configuration validates before applying changes.

## Keep one window centered on an ultrawide

In Settings → Windows choose the lone-window width and alignment, or set:

```toml
fullscreen-width = 0.6
single-window-alignment = 'center'
```

Set the width to `1.0` to fill the display again. See the
[full explanation](../README.md#lone-windows-and-fullscreen-width).

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

## Use one side of a modifier

```toml
[modifiers]
alt = 'left'
```

This lets right Option type characters while StripMuxX bindings use left Option.
Values are `both`, `left` and `right`. Remove the setting to use both sides.

## Send an app to a desktop only when it launches

```toml
[[on-window-detected]]
if.app-id = 'net.imput.helium'
if.app-has-other-windows = false
run = 'move-node-to-workspace 5'
```

The rule moves only the window an app opens when it launches, while StripMuxX manages
no other window of it. Windows the app opens later, such as login or dialog windows,
open on the current desktop, next to the app, instead of following the rule.
Settings › Automation › Rules offers this as **App windows › Only the app's first window**.

