<p align="center">
  <img src="resources/app-icon/icon.png" width="96" alt="StripMuxX logo">
</p>

<h1 align="center">StripMuxX</h1>

<p align="center">One scrolling strip of windows on each macOS space.</p>

<p align="center">
  <a href="https://github.com/gfavaro/StripMuxX/releases">Download</a> ·
  <a href="#settings">Settings</a> ·
  <a href="docs/FORK.md">Fork guide</a> ·
  <a href="HACKING.md">Development</a> ·
  <a href="docs/README.md">Documentation</a>
</p>

New to StripMuxX? Start with the [quick start](docs/QUICK_START.md), learn the
[concepts](docs/CONCEPTS.md), then read [the strip](docs/LAYOUTS.md) and the
[recipes](docs/RECIPES.md). Use the [command guide](docs/COMMANDS.md) alongside
`stripmuxx --help`.

Contributing? Read our [core principles](docs/PRINCIPLES.md) and
[contributor guide](CONTRIBUTING.md), including the repository-local agent skill.

By gfavaro, based on [ZimengXiong/WinMux](https://github.com/ZimengXiong/WinMux).
Automatic updates are disabled.

## What it does

- **Your spaces, as macOS has them.** A workspace is a macOS space.
  Control-1 … Control-9, Control-arrow and trackpad swipes switch spaces as usual,
  and Mission Control still creates, orders and removes them. StripMuxX can add the
  spaces `persistent-workspaces` lists; it never removes one.
- **One strip per space.** Tiled windows are columns laid left to right. When they
  are wider than the display the strip scrolls to keep the focused column in view,
  as in [niri](https://github.com/YaLTeR/niri) or PaperWM. A column is one window or
  a vertical stack of windows.
- **Widths you choose.** New columns take `[scrolling] column-width` of the display;
  Alt-R steps through width presets, and a column can be pinned to a screen edge
  while the rest scrolls beside it.
- **A minimap.** The whole strip at a glance; click or drag a column to focus or
  reorder it.
- **Strips survive.** Switching away and back, moving windows between spaces and
  displays, Mission Control renumbering and restarts all keep each space's strip.
- **Floating when you want it.** Toggle any window, or float apps by rule; floating
  windows keep their own frames above the strip.
- **Free-size strip columns (experimental).** `stripmuxx layout free-size` makes a
  window part of the strip while preserving its preferred width, height and
  vertical placement. `layout tiling` returns to managed sizing; `layout floating`
  removes it from the strip. This implementation is not yet build-validated.

There are no other layouts, virtual workspaces, projects, sidebar, tabs or window
borders. A WinMux or AeroSpace-style configuration that uses them still loads, and
`stripmuxx doctor` lists what it ignored.

## Default shortcuts

| Keys | Action |
| --- | --- |
| Alt-H / Alt-L | Focus the column left / right |
| Alt-J / Alt-K | Focus down / up within a stack |
| Alt-1 … Alt-8, Alt-9 | Focus a column by place; Alt-9 is the last |
| Alt-Shift-H / Alt-Shift-L | Move the column left / right; out of a stack, make it a column |
| Alt-Shift-J / Alt-Shift-K | Move a window down / up within its stack |
| Cmd-Shift-H / Cmd-Shift-L | Stack the window into the column left / right |
| Alt-R, Alt-Shift-R | Next width preset, full width |
| Alt-C | Center the focused column |
| Alt-Minus / Alt-Equal | Narrower / wider by 50 points |
| Cmd-Shift-I | Balance sizes |
| Alt-Shift-T | Float or tile the window |
| Alt-Shift-M | StripMuxX fullscreen |
| Ctrl-Alt-M | Show the minimap |
| Ctrl-1 … Ctrl-9, Ctrl-0 | Space 1 … 9, 10 |
| Ctrl-H / Ctrl-L | Previous / next space |
| Alt-Shift-1 … Alt-Shift-9 | Move the window to space 1 … 9 |
| Ctrl-Shift-H / Ctrl-Shift-L | Move the window to the previous / next space, and follow it |

Option with a two-finger horizontal trackpad scroll pans the strip. All shortcuts
are editable in Settings → Shortcuts; the reference configuration is
[`resources/default-config.toml`](resources/default-config.toml).

## Settings

Open Settings from the StripMuxX menu. The window is resizable, and the controls
support keyboard navigation, accessible labels and values, Reduce Motion, Reduce
Transparency, and increased contrast.

| Page | Options |
| --- | --- |
| General | Start at login, configuration reload, restoring strips, putting windows back on quit, and the setup check |
| Shortcuts | Presets, editable shortcuts, modifier sides and binding modes |
| Spaces | Spaces to keep (`persistent-workspaces`) and space shortcuts |
| Displays | Connected displays, and the display each added space goes to |
| Windows | New windows, lone-window width and alignment, column widths and centering, the minimap, the Option pan and learned minimum sizes |
| Appearance | Theme, menu-bar indicator and window spacing |
| Automation | Window rules, and startup and event commands |
| Configuration | Complete TOML editor, validation and advanced reference |

Settings writes the TOML configuration and reloads it; your drafts stay in place
when you switch pages, and a failed save can be retried. Each space's saved strip
and learned application sizes remain local session data. See
[configuration and migration](docs/CONFIGURATION.md).

## The menu

The menu bar item shows a strip icon, or the focused space's number. Its menu
offers Center Column, Show Minimap, Cycle Column Width, Pin Column Left/Right,
Retile, Balance Sizes, Fullscreen and **Always Float “App”…** (hold Option for
**Float Windows by Title…**). When the space has floating windows, **Add “App” to
Strip** (a submenu when there are several) puts one into the strip whether or not it
has focus. The rest under Commands: spaces, displays,
focus, moves, stacking, resizing, Toggle Floating, Undo Layout Change, Refresh
Spaces and Reload Config. Shortcuts shown come from the active mode.

Run `stripmuxx doctor` to inspect the loaded config path, permissions, displays and
spaces, the tiling state, conflicting window managers and configuration that no
longer applies. Review local paths and app names before sharing a report.

## Lone windows

A window alone on a space is limited to a shape, not a share of the screen width, so it looks
the same on a laptop and on an ultrawide:

```toml
single-window-aspect-ratio = 1.6   # at most 1.6 times as wide as it is tall; 0 (default) fills the width
single-window-alignment = 'center' # center | left | right

[display.'Built-in']
single-window-aspect-ratio = 1.2
```

`single-window-aspect-ratio` accepts `0` to `6`; the default is `0`, which lets a lone window fill the width, and `1.6` is a 16:10 window.
Known application minimum widths take priority, up to the available width. A second column
ends the limit. A `[display.<pattern>]` table overrides the ratio and the alignment for one
display, and omitted keys inherit the global values; named display patterns beat
main/secondary, and exact UUID, hardware and display-number selectors beat name patterns.
StripMuxX's `fullscreen` command always fills the display, and macOS native fullscreen is
unaffected.

## Restarts

With `[native-spaces] restore-layouts = true`, the default, each space's strip is
saved as you work and restored after StripMuxX or the Mac restarts: columns, stacks,
widths, the pinned column and floating windows. Windows are matched by app and
identity; after a reboot, an app's windows are paired in order. A space whose
windows have not all returned keeps its saved strip, protected from autosave, for up
to 90 seconds before the windows that did return are arranged without the rest.
With `restore-frames-on-quit = true`, quitting or `enable off` puts tiled windows
back where they were before tiling.

## Launching apps

A shortcut that opens a new window helps you launch an app onto the current space
instead of returning to a window elsewhere. Tap bindings fire on a lone modifier:

```toml
[mode.main.binding-tap]
    left-alt = 'exec-and-forget /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --profile-directory="Default"'

[mode.main.binding]
    # Disable the native "Hide App" shortcut.
    cmd-h = []
    cmd-e = 'exec-and-forget osascript ~/Documents/scripts/launchFinderWindow.scpt'
```

```applescript
# ~/Documents/scripts/launchFinderWindow.scpt
tell application "Finder"
    if it is running
        tell application "System Events" to tell process "Finder"
            click menu item "New Finder Window" of menu "File" of menu bar 1
        end tell
    else
        activate
    end if
end tell
```

## Installation

Download a ZIP from [StripMuxX releases](https://github.com/gfavaro/StripMuxX/releases)
and extract `StripMuxX.app`, or build this fork with
`make fork-build BUILD_NUMBER=<new-number>`, then install
`.release/StripMuxX.app` as described in [HACKING.md](HACKING.md). Fork builds retain
the configured local signing identity, are not notarized, and have automatic
upstream updates disabled.

The `stripmuxx` command can be linked into your PATH after installation:

```sh
ln -s /Applications/StripMuxX.app/Contents/MacOS/stripmuxx-cli /opt/homebrew/bin/stripmuxx
```

The link follows future app updates. Choose another existing directory in PATH
if Homebrew is not installed.

## Configuration file

StripMuxX's configuration is `${XDG_CONFIG_HOME:-~/.config}/stripmuxx/stripmuxx.toml`.
On first launch it writes the reference configuration there; it never reads or
copies another window manager's configuration. `--config-path` selects an explicit
file. Keys StripMuxX does not support are skipped and listed by `doctor`. See
[app isolation](docs/FORK.md#app-isolation) for details.

## Credits

StripMuxX is based on ZimengXiong/WinMux. Configuration and command support also
build on [AeroSpace](https://github.com/nikitabobko/AeroSpace). The scrolling strip's
geometry adapts [Dinky](https://github.com/mikker/Dinky); see
[Dinky's MIT license](docs/licenses/Dinky-MIT.txt).
