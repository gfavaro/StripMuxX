# Ergonomic keyboard preset (opt-in)

The default shortcuts intentionally remain unchanged for existing users.
An alternative complete reference config is available at
`resources/shortcut-presets/ergonomic-default.toml`.

It uses **Control + Option + H/J/K/L** for focus,
**Control + Option + Shift + H/J/K/L** to move windows,
**Control + Option + R** (next width),
**Control + Option + Shift + R** (previous width),
**Control + Option + S** (minimap), and
**Control + Command + 1…9** for space switching.
The full config also remaps the other default shortcuts to avoid plain
Option-letter combinations and common Command+Shift shortcuts.

This is a full alternative config, **not an additive TOML snippet**. If you
want to try it, copy it to a separate file and launch StripMuxX explicitly with
that configuration, after inspecting the key bindings. Do not overwrite your
active configuration. Existing settings, custom rules and personal bindings
are not automatically migrated. Some chords may still conflict with
user-defined macOS or third-party shortcuts (for example keyboard managers).
The preset has not been manually verified with different keyboard layouts.
