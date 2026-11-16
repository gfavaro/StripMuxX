# Concepts

StripMuxX works on macOS **spaces**: the Spaces you see in Mission Control. A
workspace in StripMuxX's commands and configuration is one of those spaces,
named by its number, as Control-1 … Control-9 count them. macOS owns the spaces:
you create, reorder and remove them in Mission Control, and each display shows one
space at a time.

Each space holds one horizontal **strip**. Tiled windows are its **columns**, laid
out left to right; when they do not fit, the strip scrolls so the focused column
stays in view. A column is one window or a vertical **stack** of windows sharing the
column's width. **Floating** windows sit above the strip and keep their own frames.
See [the strip](LAYOUTS.md).

Switching spaces (`workspace 2`, Control-arrow or a trackpad swipe) leaves every
strip as it was. Moving a window to another space or display adds it to that
space's strip. macOS cannot move a space between displays, so
`move-workspace-to-monitor` moves the space's windows, with their strip, to the
space the other display shows.

Each strip belongs to its space, even when Mission Control renumbers it, and
StripMuxX restores it after a restart. Fullscreen apps get their own Spaces from
macOS; those have no strip. StripMuxX's `fullscreen` command instead widens a window
within its space. See
[configuration and session data](CONFIGURATION.md#configuration-versus-session-data).
