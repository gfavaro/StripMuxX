# StripMuxX identity and maintenance

StripMuxX keeps one scrolling strip per native macOS space. It builds on
[WinMux](https://github.com/ZimengXiong/WinMux) and AeroSpace's configuration and
command model, keeping only the scrolling strip: virtual workspaces, projects, other
layouts, the sidebar, tabs, borders and gesture handling are not part of it. It is
maintained independently and does not synchronize with WinMux.

## Repository workflow

- `origin`: https://github.com/gfavaro/StripMuxX.git
- `main`: where all work happens. Commit directly to it and push once `make check`
  passes; there are no feature branches or pull requests. Never rebase or
  force-push it.

```sh
git switch main && git pull --ff-only
# ...commit, run make check, then:
git push origin main
```

## App isolation

Release app: `StripMuxX.app`, bundle ID `com.gfavaro.stripmuxx`.
Debug app: `StripMuxX-Debug`, bundle ID `com.gfavaro.stripmuxx.debug`.
The CLI packaged in the release is `Contents/MacOS/stripmuxx-cli`; it connects to the
fork socket, not the original app. Debug CLI builds connect to the debug fork.
The app's displayed name and bundle identity are StripMuxX. Configuration lives in the dedicated `stripmuxx` folder and is never imported from
another window manager. Application Support uses `StripMuxX`, so layout and recovery
state stay separate from other WinMux builds. Login registration,
diagnostics, and sockets remain separate. No original launch agents are deleted.

The owned config is `${XDG_CONFIG_HOME:-~/.config}/stripmuxx/stripmuxx.toml`.
When it is missing, the reference configuration is written there.
`--config-path` overrides this selection. Explicitly
sharing a config makes settings edits shared as well. Never run two window managers
at once: distinct bundle IDs do not prevent competing window manipulation.

## Local build and installation

### Spaces across displays

macOS decides which space each display shows. Selecting a space showing on
another display focuses it there; nothing moves between displays except by an
explicit `move-node-to-monitor` or `move-workspace-to-monitor`. Forced assignments
only choose where `persistent-workspaces` creates missing spaces.

### Menu bar and Settings

The tray is owned by `NativeActionMenu`; Settings is `ShortcutSettingsView`.
Settings → Appearance → Menu bar chooses Icon or Workspace: the icon shows a strip
of columns in color or monochrome, and Workspace shows the focused space's number.
`[menu-bar]` stores these preferences in TOML. Legacy preferences are imported once.
See [configuration](CONFIGURATION.md).

For architecture and validation commands, see [HACKING.md](../HACKING.md).

### Building

Xcode and the toolchain in `.swift-version` are required; `make xcodeproj` installs
the pinned XcodeGen helper if absent. The build has no Apple team dependency:

```sh
make check
make fork-build BUILD_NUMBER=1
```

Outputs: `.release/StripMuxX.app` and a version/build-number ZIP. The build is not
notarized. By default it uses an ad hoc signature. To keep macOS privacy permissions
across local builds, the script reads a signing identity name from
`${XDG_CONFIG_HOME:-~/.config}/stripmuxx/signing-identity` (or `CODESIGN_IDENTITY`);
the same certificate and bundle ID must be retained. CI builds use ad hoc signing;
release builds import the persistent identity from Actions secrets.
The build command does not install, launch, or replace any app, and the old upstream
`make install` target is intentionally disabled. Install with the script:

### Installing a build

```sh
python3 script/install_fork.py --app .release/StripMuxX.app --dry-run   # checks only
python3 script/install_fork.py --app .release/StripMuxX.app --install
```

`--install` backs up the installed app (outside `/Applications`), quits it, replaces it,
relaunches it, and then compares the spaces, display layout, config checksum, window
assignments and focus with a snapshot taken before. It writes a JSON report to
`.release/install-<id>.json`. Requirements and results:

- The build number must be higher than the installed one (`make fork-build BUILD_NUMBER=N`),
  and the signing identity must match, or the script refuses before touching anything.
- `validated`: installed and nothing changed. `needs_review` says why in `reason`
  (for example `focus_changed_during_validation`, which only means you used the Mac while
  it checked; the new build is installed and running). `blocked_locked` or
  `installed_pending_validation` with `session_locked`: the screen was locked, which hides
  every window from StripMuxX; unlock and run `--resume <report>`.
- If the new app fails to start, the script restores the backup (`rolled_back`).
- To go back to the previous build on purpose: `--rollback <report>` with the report of the
  install you want to undo.
- To uninstall, quit StripMuxX and delete `/Applications/StripMuxX.app`. Its config
  (`~/.config/stripmuxx/`) and saved layouts (`~/Library/Application Support/StripMuxX/`)
  are not touched; remove them too for a clean slate.

## CI and releases

CI runs on PRs and on demand; pushes to `main` do not build. Pushing a `gf-v*`
tag runs the release workflow, which builds, signs and publishes the app ZIP.
Signing import has a two-minute timeout. Hosted runners install certificate trust
in the admin domain with passwordless, noninteractive `sudo -n`; user-domain trust
can display a prompt and stall headless jobs. The release workflow calls
`script/cleanup_signing_identity.py` even after failed/canceled imports. It is
restricted to disposable GitHub-hosted runners. It deletes only our temporary
keychain, certificate/archive and database sidecars. Keychain API deletion has a
30-second timeout and direct file removal as fallback; inability to remove files
still fails cleanup. The workflow also bounds the cleanup step to two minutes.

`remove-trusted-cert` is deliberately avoided: it can hang even with sudo, as
reported in [runner-images#12116](https://github.com/actions/runner-images/issues/12116).
The remaining public trust metadata is discarded with the runner VM, whose disposal
is documented in [GitHub's runner lifecycle](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners).
Tests use fake commands and synthetic files, never local keychains.
Bot-created synchronization PRs do not rely on the normal PR event: synchronization
explicitly dispatches CI on its branch. Check that run in Actions before merging.
If dispatch fails, run CI manually on that branch. GitHub Actions must be allowed
to create pull requests in the fork's Actions settings.
Enable GitHub Actions for this fork if disabled. Releases run only on `gf-v*` tags,
test the code again, and require the tagged commit to be part of `main`.
The tag suffix must match `VERSION`. Build numbers use the GitHub run number.
Increment `VERSION` before a new release, then:

```sh
git tag gf-v0.5.7 main  # example; must match VERSION
git push origin gf-v0.5.7
```

There is no updater: the app contains no update framework, feed or public key. Releases are
built and installed with the scripts above.
Apple certificate-based signing/notarization is a separate future setup.

## Bootstrap verification

Local tests/build results should be recorded separately from hosted CI. Publishing
the branch does not prove the hosted pinned-toolchain build passed. Existing
upstream PRs retain their independent defaults and do not receive fork branding.

Bootstrap local verification: 631 Swift tests and 9 Python tests passed. The
release app and its release CLI were built with local Apple Swift 6.4 / Xcode 27,
not the pinned CI Swift toolchain. Ad hoc signatures and bundled fork metadata
were verified. No app was installed or launched as part of bootstrap verification.
