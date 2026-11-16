# Quick start

Install StripMuxX from the [releases page](https://github.com/gfavaro/StripMuxX/releases)
using the steps in [HACKING.md](../HACKING.md#build-and-check), then open
StripMuxX and grant Accessibility access when macOS asks. StripMuxX uses that access
to read and position app windows, and to switch spaces.

In System Settings › Desktop & Dock, turn off **Automatically rearrange Spaces based
on most recent use**, so space numbers stay put. Create the spaces you want in
Mission Control, or list them in `persistent-workspaces` and StripMuxX adds the
missing ones.

Open two ordinary windows. Each becomes a column on the current space's strip.
Alt-H and Alt-L move focus between columns; Cmd-Shift-H and Cmd-Shift-L stack a
window into the column beside it; Alt-R cycles the column's width; Control-1 … 9
switches spaces. Open Settings from the StripMuxX menu to adjust gaps, widths,
appearance and shortcuts. The commands and configuration are in the
[command guide](COMMANDS.md) and [configuration guide](CONFIGURATION.md).

Settings › General has a **Setup check** for Accessibility, Spaces settings and other
window managers; it opens once on first launch if something needs attention. Run
`stripmuxx doctor` in Terminal to see the config path, permissions, spaces and
anything in your configuration that no longer applies. For a guided overview, read
[concepts](CONCEPTS.md), then [the strip](LAYOUTS.md) and [recipes](RECIPES.md).
