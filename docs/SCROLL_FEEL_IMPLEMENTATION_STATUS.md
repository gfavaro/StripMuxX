# Scroll feel / free-size implementation status

Last edited 2026-11-15. This is a **partial, uncompiled implementation**,
not a release endorsement. The owner explicitly requested GitHub commits
without running a build or tests.

## Implemented (requires macOS verification)

- Added `free-size` as a `layout` command mode.
- Added per-window temporary preferred native frame.
- `layout free-size` puts a floating window onto the strip with a fixed
  column width derived from its current native frame.
- `layout tiling` from free-size restores prior column width metadata.
- Free-size strip geometry retains preferred height and clamped vertical
  placement while horizontal placement follows scrolling columns.
- Existing `layout tiling floating` behavior remains distinct.

Manual trial commands on a disposable desktop:

```sh
stripmuxx layout free-size
stripmuxx layout tiling
stripmuxx layout floating
```

## Known missing functionality / risks

- No persistence for free-size mode and preferred frame after restart.
- Manual window resize does not yet synchronize preferred frame.
- Free-size currently applies to a *single-window* column, not a stack.
- Width remains subject to the existing fixed-column geometry and minimums.
- Minimap and Settings do not distinguish free-size from tiled.
- Direct pan physics, momentum, focus/activation and AX latency were **not**
  modified by these commits.
- No `make check`, Swift compilation, integration or physical testing executed.
  Treat these commits as experimental and revert if the new mode misbehaves.

## Next gates

1. Run `make check` and fix compiler failures before deploying.
2. Verify floating -> free-size -> tiled -> floating transitions on a disposable Space.
3. Add persisted free-size mode/frame to frozen strip with backwards-compatible decoding.
4. Detect user-driven free-size resize and adjust desired width/height.
5. Instrument and improve Option pan based on captured event phases,
   frame-request rates and input-to-frame latency. Do not guess at animation.
6. Validate physical trackpad, Spaces, display changes and restoration.

See `docs/QA_AUDIT.md` for the last *verified* baseline.
