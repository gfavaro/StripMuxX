# Concepts

StripMuxX works on macOS **desktops**: the Spaces you see in Mission Control. A
workspace in StripMuxX's commands and configuration is one of those desktops,
named by its number, as Control-1 … Control-9 count them. macOS owns the desktops:
you create, reorder and remove them in Mission Control, and each display shows one
desktop at a time.

Each desktop holds one horizontal **strip**. Tiled windows are its **columns**, laid
out left to right; when they do not fit, the strip scrolls so the focused column
stays in view. A column is one window or a vertical **stack** of windows sharing the
column's width. **Floating** windows sit above the strip and keep their own frames.
See [the strip](LAYOUTS.md).

Switching desktops (`workspace 2`, Control-arrow or a trackpad swipe) leaves every
strip as it was. Moving a window to another desktop or display adds it to that
desktop's strip. macOS cannot move a desktop between displays, so
`move-workspace-to-monitor` moves the desktop's windows, with their strip, to the
desktop the other display shows.

Each strip belongs to its desktop, even when Mission Control renumbers it, and
StripMuxX restores it after a restart. Fullscreen apps get their own Spaces from
macOS; those have no strip. StripMuxX's `fullscreen` command instead widens a window
within its desktop. See
[configuration and session data](CONFIGURATION.md#configuration-versus-session-data).
