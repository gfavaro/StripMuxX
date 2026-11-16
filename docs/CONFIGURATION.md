# Configuration

StripMuxX keeps one scrolling strip per macOS desktop; see [the strip](LAYOUTS.md).
`[native-spaces] restore-layouts = true`, the default, restores each desktop's strip
after StripMuxX or the Mac restarts; `restore-frames-on-quit = true` puts tiled
windows back where they started on quit or `enable off`. See
[Native Spaces](NATIVE_SPACES.md) for how desktops are observed and switched.

A WinMux or AeroSpace-style configuration that sets features StripMuxX does not have
(virtual workspaces, other layouts, a sidebar, tabs, borders, dimming and similar)
still loads: those keys, tables and commands are skipped, and `stripmuxx doctor` lists
them under "Ignored, not supported by StripMuxX". A binding made only of such commands is not registered.

For TOML editor completion, use the checked-in
[StripMuxX JSON Schema](schemas/stripmuxx.schema.json) with a TOML editor that
supports JSON Schema. Keep the schema beside your local documentation or use its
raw GitHub URL after publication. It describes common field types and choices;
StripMuxX's parser and runtime remain authoritative for command strings, monitor
selectors and cross-field rules. The parser rejects unknown keys; the schema
adds editor completion and earlier feedback.

The schema is Draft 2020-12. To run the same fixture check used by `make check`,
install the pinned Python dependencies into a local virtual environment:

```sh
python3 -m venv .deps/config-schema
./.deps/config-schema/bin/pip install --requirement requirements-schema.txt
./.deps/config-schema/bin/python script/test_config_schema.py
```

For Visual Studio Code with the [Even Better TOML extension](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml),
associate the local schema from workspace settings (adjust the path if your config lives elsewhere):

```json
{
  "evenBetterToml.schema.associations": {
    "(^|[/\\\\])stripmuxx\\.toml$": "./docs/schemas/stripmuxx.schema.json"
  }
}
```

For example, `center-focused-column = "on-overflow"` receives completion, while
`center-focused-column = "sometimes"` is flagged because it is not a supported
choice. Keys of removed features are flagged too, although the parser skips them. This is editor assistance; `stripmuxx doctor` and the
application parser remain authoritative.

The loaded TOML file is the source of behavior and appearance preferences.
Settings edits that file, validates it and reloads the app. Raw edits and Settings
changes use the same configuration fields. `stripmuxx doctor` reports the loaded
path; `stripmuxx reload-config --dry-run --no-gui` validates without writing or
publishing changes. The default file is `~/.config/stripmuxx/stripmuxx.toml`.

## Persistent desktops

```toml
config-version = 2
persistent-workspaces = ['1', '2', '3', '4', '5']
```

StripMuxX adds macOS desktops until the highest number listed exists, one at a time
and each confirmed before the next. It never removes a desktop; manage them in
Mission Control. Text names have no effect: desktops are numbered, as Control-1 …
Control-9 count them. A new desktop goes to the display
`[workspace-to-monitor-force-assignment]` names for its number, else the main one:

```toml
[workspace-to-monitor-force-assignment]
'4' = ['secondary']
```

For compatibility, the old `minimum-workspace-count` is converted to explicit
persistent names: a count of 4 with `['3']` becomes `['3', '1', '2', '4']`.
Automatic conversion accepts counts from 0 to 4096.

## Menu bar

```toml
[menu-bar]
indicator = 'icon'          # icon or workspace (the desktop number)
icon-appearance = 'color'  # color or monochrome
```

Menu-bar settings apply on reload and have no runtime fallback to UserDefaults.
The icon shows a strip of columns. Color uses the macOS system accent; monochrome
is a template icon that follows the menu bar. An active keyboard mode tints either
icon. The text indicator shows the focused desktop's number.

## Migration and backups

At startup, an editable config is migrated before loading. Legacy
`doubleSidedWindows`, `menuBarIndicator` and `iconAppearance` preferences are
imported only when the corresponding TOML key is absent. Explicit TOML values
win. The old preference keys are removed only after a validated write succeeds.
Removing a TOML key later restores its default; an old preference cannot return
on the next launch.

Changed files use the normal atomic config writer. The original is saved as
`stripmuxx.toml.backup.1`; up to five backups are kept. Invalid configuration is not
rewritten and its legacy preferences remain available for retry. Migration is
idempotent. Parsing, diagnostics and dry-run reloads do not modify files.

## Configuration versus session data

TOML holds user-selectable behavior, appearance, shortcuts, automation and the
displays for added desktops. Copying the file reproduces those choices.

Each desktop's saved strip, windows' original frames and learned app minimum sizes
are runtime state. The last-opened Settings page is UI state. These remain outside TOML and
do not override its preferences. macOS permissions and login-service registration
are OS state; the TOML `start-at-login` preference controls the desired registration.

## App theme

Set the root-level key before any TOML table:

```toml
appearance = 'system' # system, light, or dark
```

The same value appears in Settings → Appearance → Theme. It applies to StripMuxX
windows: Settings and the minimap. System follows macOS Light/Dark appearance and
updates when macOS changes it. Light and Dark override the system for StripMuxX.
Reduce Transparency and Increase Contrast continue to apply in every theme.

## Mode leaders

Binding modes support optional `timeout-ms = 1500`, `show-indicator = true`, and
`indicator-color = '#5E9EFF'` in `[mode.<name>]`. Defaults are no timeout and no
indicator. `main` never times out or displays a badge. The timeout starts at entry
and restarts after accepted bindings finish. Unbound keys pass through and do not
reset it. Set `exit-on-unbound-key = true` to return to `main` when an unassigned
key is pressed, passing that key through to the focused app. This is opt-in and
ignored in `main`. Modifier-only taps do not exit the mode. Configure `esc = 'mode main'` explicitly; append `'mode main'` to a
binding's command array for one-shot use. Re-entering a mode starts a fresh session.

The existing icon gains the mode color; the desktop indicator gains ` | L` for
Leader. The tooltip/accessibility label gives its full name. Custom colors are
adjusted for native menu-bar contrast. No extra overlay window or countdown runs.
Shortcut recording suspends the deadline and badge; resuming starts a fresh interval.

### Settings saves and mode controls

Shortcuts → Binding modes exposes each configured mode's inactivity timeout,
indicator toggle and color, and whether an unassigned key exits the mode. Add mode creates a named mode with Escape to return to
main. Add its entry shortcut in Configuration; existing shortcuts are preserved.
The main mode's timeout and mode badge remain disabled.

Ordinary Settings controls save automatically. Text fields save after a short pause
(650 ms) or when leaving the field/page. Numeric fields commit on Return or when
editing ends; toggles, pickers and recorded shortcuts apply directly. Invalid edits stay visible for correction. Failed writes retain
the draft and provide Retry. Opening or reloading a page does not save its values.
Existing rule and display-assignment edits also autosave; creating or deleting
entries remains an explicit action. The complete TOML editor in Configuration
keeps Validate and Save and apply, including stale-file conflict protection.

## The strip

```toml
[scrolling]
column-width = 0.49
width-presets = [0.25, 0.3333, 0.5, 0.6667, 0.75, 1.0]
gesture-enabled = true
gesture-sensitivity = 1.0
gesture-smoothing = 0       # experimental: ms to ease windows toward the fingers; 0 = off
minimap-enabled = true
center-focused-column = 'never'   # never, on-overflow or always
minimap-hold-modifiers = []       # e.g. ['ctrl', 'alt']
keep-window-height = false        # a lone window keeps its opening height, at the top
```

`column-width` is a new column's width as a share of the display, gaps included.
`scrolling-width next|previous|full` steps the focused column through
`width-presets` or fills the display, and `scrolling-center` centres it. With
`keep-window-height`, a window alone in its column keeps the height it opened with,
aligned to the top, instead of filling the column; stacks still share the full
height.

Option plus a two-finger horizontal trackpad scroll pans the strip
(`gesture-enabled`, `gesture-sensitivity`); plain scrolls stay with the app. A
fitting strip is centered. An overflowing strip clamps at both ends; explicit
centering respects those bounds. Scrolled-out columns leave a 25-point edge preview.

`center-focused-column` decides where the strip goes when focus lands on a column:
`never` scrolls only as far as needed to show it, `on-overflow` centres it when it
would otherwise be partly off screen, and `always` centres it. It applies to
keyboard focus and minimap clicks.

`scrolling-focus 1-9|first|last` focuses a column by its place on the strip, with 9
the last column as with browser tabs; `scrolling-move 1-9|first|last` moves the
focused column there. A horizontal `move` takes a window out of a stack to the left
or right, and `join-with` puts it into a neighbouring column.

`scrolling-pin left|right` pins the focused column to that screen edge at full height
while the rest of the strip scrolls in the space beside it; the same command unpins
it. The pinned column keeps its width, leaves the strip and the minimap, and blocks
edge previews on its side. Pins are saved with the desktop's strip, so they return
after a restart.

The minimap shows the strip on its desktop's display, with app icons and titles,
with a dashed outline for the visible area. Click a column to focus it; drag it
sideways to reorder the strip. It appears while navigating and fades after 1.5
seconds of inactivity. With `minimap-hold-modifiers` set, holding exactly those keys
keeps it up. Run `scrolling-minimap` or choose **Show Minimap** in the menu to keep it
open; Left/Right select, Return activates and Escape dismisses. Fresh configurations
bind Control–Option–M:

```toml
[mode.main.binding]
alt-ctrl-m = 'scrolling-minimap'
```

StripMuxX adapts the scrolling-strip geometry described by [Dinky](https://github.com/mikker/Dinky); see [Dinky's MIT license](licenses/Dinky-MIT.txt).
