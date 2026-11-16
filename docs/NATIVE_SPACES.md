# Native Spaces

StripMuxX works on macOS spaces and keeps one scrolling strip on each.
It observes which spaces exist and which one each display shows, switches spaces
and moves windows between them on request, and lays out the showing spaces' strips.
It never changes system settings and never removes a space. Physical validation so
far covers one SIP-enabled macOS 27.2 host; see [validation](#validation).

## Observation

Observation enumerates spaces and fullscreen Spaces per display, records window
memberships, and follows public Space/display/session/application events plus
dynamically resolved WindowServer lifecycle notifications. Active spaces' windows
are classified through Accessibility and placed on their space's strip. Missing AX
responses retain nodes; explicit WindowServer closure and confirmed process
termination remove them. Leaving a Space or disappearing from AX does not imply
closure.

Each space's strip is keyed by the space's UUID, so it survives Mission Control
reordering and renumbering. Fullscreen Spaces, and windows macOS shows on every
space or on unknown Spaces, are observed but not tiled. A window assigned to all
spaces (Options › Assign To › All Spaces) is tiled on the space showing on its
display, and follows to whichever space shows next there. With several displays it
belongs to the one under its centre, never to two at once.

`stripmuxx doctor` reports native IDs, UUIDs, per-display active Spaces, membership
counts, query duration, AX classification, whether the observation is stale, the
tiling state, and per-window JSON diagnostic rows (`Window frame:`) with PID, Space
UUID, eligibility, floating state and the last calculated layout target. Targets are
cached model state, not actual AX measurements.

Queries (`list-workspaces`, `list-windows`, `list-apps`, `list-modes`,
`list-exec-env-vars`, `config`) answer from configuration and native snapshots.
Workspaces are named by space number (`%{workspace}` prints `2`), and
`--workspace 2` selects space 2; internal `__native_space_*` names never appear.
`list-monitors` answers from the real displays.

## Tiling

`NativeTilingCoordinator` applies the strip's geometry to the showing spaces.
Minimized and hidden windows are filtered from frame calculation without leaving the
strip. Floating windows keep their physical frames unless an explicit command changes
them. Layout is suspended below macOS 27, whose Mission Control overlay detection has
not been validated, and while Mission Control is open, a mouse button is down or the
observation is invalid. Accessibility permission must already exist; startup never
prompts or changes system settings. `doctor` reports the actual status.

Strip commands run inside a fence: they wait for a reconciled observation, and keep
their original space, display and window across that wait. A changed owner, focus
or reused ID cancels the command before it changes anything. Default command targets
require verified native focus; an unmanaged or fullscreen frontmost window cannot
redirect commands to a previously focused space. A binding made only of commands
StripMuxX does not support is not registered, so its keys keep reaching macOS and the
focused app.

Every queued frame write and retry requires a current generation permit, fresh
Space/process ownership and non-minimized/non-fullscreen AX state. Explicit keyboard
focus uses a two-second ownership lease so its own activation notifications can
invalidate frame batches without interrupting focus halfway through. AX calls already
dispatched cannot be recalled; this is not an atomic transaction.

A tiled window its app moves or resizes on its own is put back once it has been still
for 150 ms, up to three times in 10 seconds per place, so an app that keeps fighting is
left alone. `retile` renews that budget.

## Navigation

`workspace N` follows macOS's Control-N numbering: ordinary spaces counted across
displays in Mission Control order, skipping fullscreen Spaces. `workspace next|prev`
follows Control-arrow on the focused space's display (otherwise the display under
the pointer), fullscreen Spaces included; `--wrap-around` and `--monitor` are honored.
`workspace-back-and-forth` and `--auto-back-and-forth` return to the display's
previous space, skipping fullscreen Spaces. A navigation command cannot share a
binding with window commands.

Navigation posts a synthetic Dock swipe, adapted from Dinky (MIT) and mimi. It needs
no Mission Control keyboard shortcuts and works with SIP enabled, but it relies on
private event fields and the IOHID payload layout the Dock reads on macOS 27; earlier
systems report it as unsupported. The pointer briefly moves to the target display
when it is elsewhere and is put back. Success is never assumed: fresh topology reads
confirm the landing, a short landing is retried once from the observed Space, and a
switch that still has not landed after about a second is reported. A newer request
supersedes an older one. Without Accessibility permission macOS drops the events
silently, so the command fails up front instead.

## Moving windows between spaces and displays

`move-node-to-workspace N|next|prev` moves a window to another space, with the
same numbering as `workspace`; next/prev step through the window's display's
spaces, skipping fullscreen Spaces, and `--focus-follows-window` follows it.
`--window-id` and `--fail-if-noop` are honored. The window joins the destination
space's strip once the move is confirmed.

`move-node-to-monitor` moves a window to the space another display is showing,
through the same confirmed move, and `focus-monitor` focuses the most recent window
of the space the target display shows. `focus --boundaries all-monitors-outer-frame`
continues onto the next display's space, and `move --boundaries
all-monitors-outer-frame` past the strip's end moves the window there once the command
ends.

macOS cannot move a space to another display without SIP changes (Mission Control
can, by dragging its thumbnail). `move-workspace-to-monitor` therefore moves the
space's windows: each joins the space the target display shows, and the strip
follows. Into an empty space it arrives whole, with its columns, stacks and
floating windows; into a space that has windows its columns are appended. The macOS
space itself stays on its display, emptied, and the most recently used moved window
is focused. Windows that do not arrive stay where they were and are reported. The
source may be a space that is not showing; `--workspace N` names it.

The move uses SkyLight's `SLSBridgedMoveWindowsToManagedSpaceOperation` through a
dispatcher SkyLight does not export, found by scanning its symbol table (adapted from
Dinky, MIT). It works with SIP enabled and takes milliseconds, but a macOS update can
remove either piece; `doctor` then reports moves unavailable and the command fails
instead of guessing. Each move is confirmed by re-reading the window's Space. A window
on every space cannot be moved, since macOS already shows it everywhere.

`on-window-detected` rules that run `move-node-to-workspace` move windows opened after
StripMuxX starts; windows that existed at startup are never moved by a rule, including
ones first seen later when their space is visited.

## Adding spaces

`persistent-workspaces` makes StripMuxX add spaces until the highest numeric entry
exists, one per confirmed topology read, after the displays have settled. Each new
space goes to the display `workspace-to-monitor-force-assignment` names for its
number, otherwise the main display. macOS appends on that display, so display-order
numbering can shift existing spaces; creation does not guarantee lasting ordinal
ownership. A failure stops further attempts until a reload or a display change.

## The strip and the pan

Columns scrolled out of view stay at the display edges as 25-point previews (or behind
visible columns next to another display); they are never parked in a corner, so they
stay on their space and reachable. Overlap order uses AX raises, which do not
activate the window's app.

macOS keeps three- and four-finger swipes for switching Spaces, so StripMuxX pans with
**Option + two-finger horizontal scroll** on a trackpad (`[scrolling] gesture-enabled`). Those scroll events are consumed, including the momentum
macOS adds after the fingers lift, so the pan moves with the system's own scrolling
curve; other scrolls, mouse wheels and fullscreen Spaces are untouched. When the
momentum ends, the column nearest the middle is revealed and focused. The minimap
shows while panning.

## Mouse

There is no drag overlay. Layout pauses while a mouse button is down. On release, a
tiled window whose size changed keeps it: its column's width, or its share of a
stack's height (a lone window's width becomes its manual width). A tiled window
dropped onto another tile of its space swaps with it. Anything else returns to its
place.

## Persistence

Each space's strip is stored in
`~/Library/Application Support/StripMuxX/native-space-layouts-v1.json`, keyed by Space
UUID. Only spaces present in the current observation are saved. Restore binds only
uniquely matched windows already on that space; it neither launches apps nor moves
windows between spaces. A missing or ambiguous window keeps the complete saved
strip pending and protected from autosave. After a Mac restart window identities and
terminal titles often change, so when an app has exactly as many unmatched windows on
the space as it saved, they are paired in creation order. A strip still incomplete
after 90 seconds is restored without the windows that never returned, and the space
is saved again as it is. A corrupt or newer-version file is preserved and reported.
Set `[native-spaces] restore-layouts = false` to disable loading and saving; existing
files are retained.

Quitting StripMuxX or `enable off` puts each tiled window back where it was before
tiling first moved it, if it is still on that space and the space is showing; a
window on a hidden space stays where it is, since reaching it would take a space
switch. The original frames are kept in memory only. Set `restore-frames-on-quit =
false` to leave windows where tiling put them.

## Hooks

`after-startup-command` runs once the first observation arrives.
`exec-on-workspace-change`, `on-focus-changed` and `on-focused-monitor-changed` run
when observation or focus synchronization sees that change, and `WINMUX_WORKSPACE`,
`WINMUX_FOCUSED_WORKSPACE` and `WINMUX_PREV_WORKSPACE` carry space numbers (empty for
a fullscreen Space).

## Failure handling and limits

Read-side SkyLight symbols are dynamically resolved behind `NativeSpaces`.
Unavailable symbols, invalid topology or a topology change during a read suspend
observation. A Space-change event immediately revokes the current observation;
superseded reads cannot publish older membership. Last successful observations may
remain visible as **stale diagnostics**, never as permission to write frames. A
topology-only audit runs every 500 ms to recover missed Space notifications;
unchanged topology does not enumerate windows or query AX. Three consecutive audit
failures suspend automatic retry until a real event or manual refresh.

These private APIs are unstable across macOS versions even with SIP enabled. No SIP
change, root helper or Dock injection is used. Missing UUIDs cannot be restored by
guessing an ordinal, and numeric Space IDs are not restart identities.

If startup configuration is invalid, shipped defaults remain available for error
display but the process stays read-only until restart. Fix the file and restart to
re-enable window management. A failed configuration reload retains the running
configuration.

## Validation

Observation, switching and window moves have been exercised with SIP enabled on Apple
Silicon/macOS 27.2 with two connected displays. End-to-end Mission Control pause/resume, physical trackpad
switching, delayed apps, multi-display movement, Stage Manager and restart
restoration on real apps remain unverified. Do not use compilation or mocked tests as
evidence that those behaviors work.

After installing a build, `script/smoke.sh` checks the running app with real windows
(`--dev` targets StripMuxX Native Dev). See [Testing](TESTING.md#review-and-verification)
for what it covers.

Run the standalone diagnostic without launching a manager:

```sh
swift run stripmuxx-native-spaces-probe --watch 30
swift test --no-parallel --filter NativeSpacesTests
make check
```

Interactive macOS checks require an unlocked space and an actual AppKit event loop.
CI fixtures verify parsing, ownership, eligibility, cancellation, configuration and
command rejection; they cannot verify private API compatibility or native UI.

`script/native-spaces-fixture.swift` supplies a disposable AppKit application with
two resizable windows, a Window menu, minimization and native fullscreen. Compile it
with `xcrun swiftc` into a temporary `.app` whose Info.plist declares the binary as
`CFBundleExecutable`, a unique `CFBundleIdentifier`, `CFBundlePackageType = APPL` and
`NSPrincipalClass = NSApplication`. Use a separately selected test space and disable
persistence in the test configuration. Never interpret fixture success as validation
of restrictive third-party apps.

## Development loop

`script/native-dev.sh run` builds a debug StripMuxX, bundles it as "StripMuxX Native
Dev" (`com.gfavaro.stripmuxx.debug`, its own command socket), signs it with the local
identity, stops the installed StripMuxX and launches the dev app with
`~/.config/stripmuxx/native-spaces-test-144.toml` (or `WINMUX_NATIVE_CONFIG`). Commands
go to it with `script/native-dev.sh cli <command>`; `script/native-dev.sh stop` quits it
and relaunches the installed app. Grant Accessibility to "StripMuxX Native Dev" once.

## Troubleshooting

- **`workspace N` reports Accessibility:** grant StripMuxX Accessibility in System
  Settings → Privacy & Security, then retry.
- **`workspace N` reports it did not land:** check `doctor` for the active Space and
  that space N exists in Mission Control. Report the macOS version; the Dock swipe
  payload is version-specific.
- **Space numbers keep changing:** turn off System Settings › Desktop & Dock ›
  Automatically rearrange Spaces based on most recent use. The setup check reports it.
- **A key binding does nothing:** run `doctor`; commands StripMuxX does not support are
  listed under "Ignored, not supported by StripMuxX", and a binding made only of them is
  not registered.
