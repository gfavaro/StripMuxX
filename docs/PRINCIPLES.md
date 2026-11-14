# StripMuxX core principles

StripMuxX arranges each macOS desktop as one horizontal, scrolling strip of columns.
macOS owns the desktops: Mission Control creates, orders and removes them, and
decides which one each display shows. StripMuxX owns only the arrangement of
windows on each desktop. Contributors should evaluate changes against that split.

## One strip per desktop

A desktop's tiled windows form a row of columns wider than the screen when needed;
the strip scrolls to keep the focused column in view. A column is one window or a
vertical stack of windows. Floating windows sit above the strip and keep their own
frames. There are no other layouts, no nested containers and no tab groups.

Each strip belongs to its desktop's identity (its UUID), not to its number: Mission
Control can reorder desktops, and a strip must stay with its desktop. Switching away
and back, moving windows between desktops and restarting StripMuxX must leave the
user's columns, stacks, widths, pinned column and floating windows as they were.

## macOS decides; StripMuxX confirms

Desktop switches and window moves between desktops are requests to macOS. Report
success only once a fresh observation confirms the result, and change a strip only
after that. When an observation is missing or stale, refuse rather than guess a
display or desktop. A command whose target changed while it waited is refused
before it changes anything.

StripMuxX never changes system settings and never removes a desktop. It may add the
desktops `persistent-workspaces` asks for. Fullscreen apps' Spaces belong to macOS
and have no strip.

## Preserve user choices

TOML owns behavior and appearance preferences. Settings edits the same configuration
that commands and reload consume. Session state and caches have separate ownership;
avoid a second preference store that can disagree with the configuration file.
A configuration written for a removed feature still loads: the parts that no
longer apply are skipped and reported by `doctor`, never silently reinterpreted.

## Native interaction, bounded work

Use the established AppKit/SwiftUI surfaces and accessible controls. Respect Reduce
Motion, Reduce Transparency and increased contrast. Validate UI changes through the
actual navigation destination, including keyboard use.

Prefer native events and coalesced, bounded work. Give asynchronous operations an
owner and cancellation or generation checks so old completions cannot affect a new
interaction. Keep geometry and policy testable separately from native side effects.
See [HACKING](../HACKING.md).

## Product inspiration hierarchy

Interaction design priority is **Spear (R. Clayton Miller / 10/GUI)** first and
**ChainYourMac** second. Niri defines the scrolling geometry and focus semantics;
OmniWM and Paneru are macOS engineering references for offscreen windows and
multiple displays. Priorities describe what to research, not permission to copy
implementation, artwork, branding or proprietary behavior.

Spear's current overlapping-window model must not be silently introduced into this
project: StripMuxX remains a scrolling-only manager with an explicit floating escape
hatch. Its spatial manipulation ideas should inform how scrolling columns are
selected, dragged, focused and moved, using native macOS gestures and accessibility.

Review references and experiments in [interaction research](INTERACTION_RESEARCH.md).

## Evidence matters

Automated tests establish model and command behavior. Physical gestures, real
application Accessibility behavior, Mission Control and display disconnects need
desktop validation. Report those separately and name what remains untested.
Preserve fork identity, user configuration and recovery data during development.

Start contributing with [CONTRIBUTING](../CONTRIBUTING.md). Implementation details
live in [HACKING](../HACKING.md), and test requirements in [Testing](TESTING.md).
