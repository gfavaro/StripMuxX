# Working in StripMuxX

Read [core principles](docs/PRINCIPLES.md) and [CONTRIBUTING](CONTRIBUTING.md) before
substantive changes. [HACKING](HACKING.md) owns architecture and development details;
[Testing](docs/TESTING.md) owns verification requirements. No external memory service
or personal skill installation is required to contribute.

Before editing, inspect `git status --short` and preserve unrelated changes. Use
the user's requested outcome to choose scope; current docs describe the baseline,
not authority to override an explicit behavior change. If code and docs disagree,
trace the relevant test and report the mismatch before choosing new semantics.

StripMuxX keeps one scrolling strip per macOS space. macOS owns the spaces
(Spaces), their order and which one each display shows; StripMuxX arranges each
space's windows as columns, a column being a window or a vertical stack. Preserve
each space's columns, stacks, widths and floating windows when changing the
implementation. There are no other layouts and no virtual workspaces.

For space navigation, moves between spaces or displays, strip edits or layout
persistence, read [.agents/skills/stripmuxx-workspaces/SKILL.md](.agents/skills/stripmuxx-workspaces/SKILL.md).
For unrelated tasks, use the relevant subsystem guidance in HACKING.

Use the [task map](docs/CONTRIBUTOR_TASKS.md) for code owners, completion criteria
and failure handling. Read [behavior examples](docs/WORKSPACE_BEHAVIOR.md) when
navigation, moves or the strip are affected.

[Native Spaces](docs/NATIVE_SPACES.md) describes how spaces are observed and
switched.

**Never push a commit to `main` that has not passed `make check` on that exact
tree.** Other sessions build and install from `main`; a commit that does not compile
or fails a test breaks their work. If you cannot run `make check`, or it fails, do
not push: report what blocked it. Writing that something is untested in a commit or
status note does not make it safe to push.

Use the checks specified in CONTRIBUTING and report manual space validation
separately. Preserve the fork's configuration, bundle/signing identity and recovery
data; follow [fork maintenance](docs/FORK.md) for the commit workflow and installation.
