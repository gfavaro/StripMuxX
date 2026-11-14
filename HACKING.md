# Developing StripMuxX

Start with [core principles](docs/PRINCIPLES.md) and [CONTRIBUTING](CONTRIBUTING.md)
for product expectations and the contribution workflow. Coding agents enter through
[AGENTS.md](AGENTS.md) and its repository-local skill.

StripMuxX keeps one scrolling strip per macOS desktop. macOS owns the desktops;
`runtime.native` (`NativeWorkspaceLifecycle`) owns everything StripMuxX does with
them: observation, the strip of each desktop (`NativeSpaceLayouts`, keyed by desktop
UUID), the tiling fence (`NativeTilingCoordinator`), desktop navigation, window moves
between desktops, layout persistence and the desktops `persistent-workspaces` adds.
The `NativeSpaces` target isolates dynamic SkyLight access and generation-checked
event reconciliation. See [native Spaces](docs/NATIVE_SPACES.md).

StripMuxX has no virtual workspaces, projects, other layouts, sidebar, palette,
overview, borders, tabs or gesture handling. Configuration keys and commands that
WinMux-family configs use for those are recognized and skipped
(`config/RemovedConfiguration.swift`), so an older configuration still loads and
`doctor` lists what it ignored.

StripMuxX builds on WinMux. Read [identity and maintenance](docs/FORK.md) for
bundle identity, configuration ownership and signing policy.
Current user-facing options are described in [README.md](README.md); the
[documentation index](docs/README.md) lists the guides.

## Build and check

Development requires macOS and Xcode. `Package.swift` defines Swift targets;
`.swift-version` pins Swift 6.4.2 for `script/setup.sh` and CI. Local Xcode’s
Swift 6.4 is accepted as the same release version. A mismatched compiler fails
before building; install the pin with Swiftly or select a matching Xcode. Release
app builds pass the selected compiler to Xcode through `SWIFT_EXEC`, so the app
and CLI use the same compiler. `Package.swift` still requires tools version 6.2.
See [dependencies](docs/DEPENDENCIES.md) for retained packages and audit decisions.
The app
supports macOS 13+, with native Liquid Glass enabled on macOS 26+.

```sh
swift build                  # Fast compilation with the active toolchain
swift test                   # Swift tests with the active toolchain
make check                   # Swift + Python checks and lockfile validation
make fork-build BUILD_NUMBER=26
```

Choose a fresh build number for each installed build. `make fork-build` generates
the Xcode project from `project.yml`, builds the release app and CLI, verifies the
signature and fork metadata, and writes `.release/StripMuxX.app` and a ZIP. It also
regenerates version/hash files in `Sources/Common`; review their diff before
committing. `WinMux.xcodeproj` and build outputs are generated artifacts.

For local releases, `script/fork-build.sh` reads the signing identity from
`${XDG_CONFIG_HOME:-~/.config}/stripmuxx/signing-identity`, unless
`CODESIGN_IDENTITY` is supplied. Retain the identity and bundle ID across installs
to preserve macOS permissions. Without a configured identity the build is ad hoc.

GitHub releases and main-branch CI artifacts use that same persistent identity.
The repository Secrets `STRIPMUXX_SIGNING_P12` (base64-encoded PKCS#12 containing
the certificate and private key), `STRIPMUXX_SIGNING_PASSWORD`, and
`STRIPMUXX_SIGNING_IDENTITY` (certificate SHA-1 fingerprint) must be configured.
The workflows import it into a temporary keychain and delete the keychain after
the build. Pull-request builds stay ad hoc and do not receive the signing key.
Signing does not notarize the app; switching from an ad hoc build may require
granting permissions once more.

The build does not install. Quit the current fork, save a ZIP backup, copy the new
bundle to `/Applications/StripMuxX.app`, verify it with
`codesign --verify --deep --strict /Applications/StripMuxX.app`, then open it.
Never rename an old bundle to `StripMuxX.app-previous-*`: archive it outside
Applications instead. `make install` is intentionally disabled. The installed
CLI is `StripMuxX.app/Contents/MacOS/stripmuxx-cli`; `--version` compares client and
server versions. Installation and validation of interactive behavior are separate
from compilation and automated tests.

See [Testing](docs/TESTING.md) for fixture isolation, asynchronous tests, rendering
coverage, regression requirements and CI reports.

## Architecture

| Area | Responsibility |
| --- | --- |
| `Sources/WinMuxApp` | SwiftUI app entry point and scene wiring |
| `Sources/AppBundle` | Window-manager runtime and native UI |
| `Sources/Common`, `Sources/Cli`, `Sources/PrivateApi` | Shared protocol/types, CLI transport, private Accessibility bridge |
| `Sources/AppBundleTests` | Tests organized alongside runtime subsystems |
| `resources`, `script`, `.github/workflows` | App resources/default config, build helpers, automation |

Within AppBundle, `tree` owns windows, desktops and the strip's tree; `layout`
computes geometry; `command` implements actions; `runtime` owns the native desktop
services; `mouse` handles the Option-scroll pan; `config` parses TOML. `ui` holds the
menu bar item, the minimap and Settings. Keep pure geometry/policy separate from
AppKit side effects.

A workspace's `rootTilingContainer` is the strip: its children are columns, and a
column is a window or a vertical `TilingContainer` of at least two windows. Floating
windows are children of the workspace itself. `Workspace.normalizeContainers()`
restores that shape after an edit; shared edits live in `tree/StripEdits.swift`.
`layoutWorkspace` lays the columns out along the strip (`layout/ColumnFrames.swift`)
and writes each window's frame; columns macOS currently hides take no place.

Strip commands run inside the tiling fence: `runCmdSeq` hands them to
`NativeTilingCoordinator.run`, which waits for a reconciled observation and refuses a
command whose target changed meanwhile. Navigation, moves between desktops, queries
and diagnostics run outside it (`runtime/NativeCommandPolicy.swift`).

Settings saves are owned by a model-local `SettingsSaveQueue`. Scalar/document,
shortcut and raw-editor saves share its ordering. Structured saves share progress,
error and retry handling; the raw editor retains its own baseline and error UI.
TOML transformations live separately from UI save orchestration. For persistence
tests, create a fresh ShortcutSettingsModel with injected SettingsConfigAccess and
SettingsDraftStore; production uses the shared instance with native access. The
workspace/config state has an explicit runtime owner as described below.

Every user-facing config key has a Settings control (a `@SettingsDraft("section.key")`
written with `persistConfig`), and every user command has a Shortcuts entry, and a
menu item when it is an action. Add the key to `docs/schemas/stripmuxx.schema.json`
(`make check` rejects parser keys missing from it) and to `SettingsNewKeysTest`,
which writes each key the way Settings does and parses the result back. Deprecated
keys, hooks and `config-version` stay config-only.

`runtime/WinMuxRuntime.swift` is the composition point for configuration, the
workspace registry, the native desktop services, focus history and native focus
holds, monitor caches, hotkeys and event history. Production uses one
process-lifetime owner. The `config`, `configUrl` and focus accessors are domain
conveniences over that owner, not independent storage. Config reload publishes value
and path together before observers run, and its gate, diagnostics, watcher and
debounce belong to the configuration owner. Monitor snapshots are immutable and
Sendable; cached main/list/sorted snapshots invalidate together on screen changes.

For focused state tests, construct a WinMuxRuntime and use `withValue` for a scoped
binding, including across suspension. Deferred work can use `runtime.task` to retain
its originating binding. A Workspace is used within its runtime binding; IDs are
unique within a registry, while object equality remains identity. Legacy serial
fixtures replace the runtime as a unit. Native window registries, UI singletons,
persistence adapters and UI singletons still have process lifetimes, so this
does not make the complete suite parallel-safe. Do not replace production runtime
state or alter AX/multitouch thread ownership to simplify a test.

Desktop navigation (`runtime/NativeSpaceNavigator.swift`) posts a Dock swipe toward
the target desktop and succeeds only once a fresh read confirms the landing.
Moves between desktops (`runtime/NativeWindowSpaceMoves.swift`) move windows by ID
and rehome them in the destination strip only after macOS confirms each arrival.
`move-workspace-to-monitor` moves a desktop's windows, since macOS cannot move the
desktop itself. `workspace-to-monitor-force-assignment` only chooses the display on
which `persistent-workspaces` creates a missing desktop.

Settings navigation lives in `ui/settings/ShortcutSettingsView.swift`. Each config
pane has a `Settings*View.swift` file; controls and TOML persistence are shared in
`SettingsControls.swift` and `SettingsConfigPersistence.swift`. A TOML edit is
validated, written, reloaded and reflected through the settings model. Menu-bar
preferences use `[menu-bar]` in TOML and publish through TrayMenuModel. UserDefaults is restricted to
session/cache data and one-time legacy preference import. Add controls to
the destination used by navigation, not to a detached alternative screen.

## Making changes

- Preserve the existing subsystem boundaries; add a file where responsibility is clear.
- Remove unreachable implementations once callers and tests have been checked.
- Keep behavior fixes separate from file moves and refactoring.
- Use existing tests first; add tests for meaningful behavior or regression cases.
- For UI changes, verify the active navigation path and inspect the installed app.
- Test multiple displays and accessibility settings when changing the minimap or menu bar item.
- Keep README/FORK and the guides in `docs/` current with behavior and configuration.
- Make commits independently understandable. Reorganize unpublished history only; never rewrite published commits.
