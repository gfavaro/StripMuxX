# Contributing to StripMuxX

Start with [core principles](docs/PRINCIPLES.md) and the short
[concepts](docs/CONCEPTS.md). StripMuxX keeps one scrolling strip per macOS desktop:
preserve each desktop's columns, stacks and floating windows, and leave the desktops
themselves to macOS.

The [task map](docs/CONTRIBUTOR_TASKS.md) provides code entry points, test filters,
completion criteria and examples. [Workspace behavior examples](docs/WORKSPACE_BEHAVIOR.md)
make current navigation, move and strip semantics concrete.

## Find the owner before changing behavior

Start with `git status --short`. Preserve changes outside your task, including
uncommitted work from other contributors. Do not reset or overwrite them to make
checks pass. Read the smallest relevant guide and trace one real entry point before
editing. If a requested feature already exists, identify the actual missing behavior
or discoverability issue rather than adding a second implementation.

[HACKING](HACKING.md) describes setup, subsystem ownership, build commands and
installation. [Fork maintenance](docs/FORK.md) describes branch targeting, app
identity and signing. Commit directly to `main` and push once `make check` passes.

For desktop and display changes, start with
`Sources/AppBundle/runtime/NativeSpaceNavigator.swift` or
`Sources/AppBundle/runtime/NativeWindowSpaceMoves.swift`, the relevant command in
`Sources/AppBundle/command/impl`, and the corresponding tests. Menu actions reach
the same commands as key bindings. Consult the architecture section in HACKING for
other subsystems.

Describe the user-visible trigger and intended outcome. Preserve existing state
owners and keep behavior fixes separate from broad refactors. When borrowing from
Dinky, niri or another window manager, compare workspace models, platform requirements
and license obligations before adapting the implementation.

## Validate and describe the result

For a bounded task, write down the trigger, expected result, affected subsystem and
one observable acceptance case. Add rejection/cancellation cases only where they
change behavior. If the request changes an existing contract, state the before/after
explicitly and update its tests and current docs together. This can be a few sentences
in your working notes; it does not require another planning document or approval.

Follow [Testing](docs/TESTING.md): use focused tests during development and run
`make check` before submitting a change. Explain any check you could not run.
For documentation-only changes, check links and examples; runtime testing adds no
evidence unless behavior or executable examples changed.

For this contributor guidance, run `python3 script/check_contributor_guidance.py`.
It checks local inline-link targets, explicit source paths and referenced XCTest
symbols in the maintained guide set. It does not validate web links, heading anchors,
or behavioral claims. Review those claims against code.

For moves between desktops or displays, cover confirmation, both desktops' strips,
refusal when the target changed, and restart. Real two-display checks should include
moving back, different usable sizes, and disconnect/reconnect when affected. Do not
claim those checks passed based on mocked monitors.

A commit message should explain the problem, resulting
behavior, validation and any remaining limitation. Update the guides when behavior or configuration changes.

Builds do not install themselves. Follow HACKING for installation and signing;
do not run competing window managers together during native validation.

## Coding agents and reusable skills

[AGENTS.md](AGENTS.md) is the repository entry point for coding agents. The tracked
[stripmuxx-workspaces skill](.agents/skills/stripmuxx-workspaces/SKILL.md) guides desktop
navigation, moves between desktops and displays, and strip work. It is repository-local so contributors can
use it without the maintainer's private memory, installed plugins or personal skills.

Add narrowly scoped skills when a subsystem needs reusable decision guidance.
Keep product principles here in the linked guides and implementation details in
HACKING; skills should route to them rather than maintain competing copies.
