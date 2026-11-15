# StripMuxX — single-pass beta verification (2026-11-14)

This supplements `QA_AUDIT.md`. The 508 XCTest + 53 Python passes documented there
are **baseline**, not evidence that the later focus/drag/swipe-diagnostics changes passed.

## Automated final gate

After fetching latest `main`, run **once**, from a clean worktree:

```sh
cd ~/Developer/StripMuxX
git pull --ff-only
make check
git status --short
```

Record the tested SHA, XCTest count, Python count, warnings, and exact failures.
The macOS CI workflow also runs on `main` and pull requests.

## Interactive checks — run together on a disposable test Space

Do not create/delete Spaces or rearrange active work windows without permission.

1. **Focus on close:** Open A, B, C; focus A → B → C; close C. Expected
   logical focus returns to B unless macOS already focused another eligible
   window. Closing B while C is focused must leave C selected.
2. **Drag a tiled window:** Start dragging the focused window from its title bar.
   Expected muted home outline, accent target outline over a neighboring tile,
   and **no tiling change until release**. Drop into another tile; the existing
   native swap behavior should match the preview.
3. **Drag safety:** Click and resize normally; move a floating, minimized,
   nonfocused or native-fullscreen window; switch a Space or display during
   drag. Expected: no wrong-window preview, no focus theft, no overlay stuck.
   This implementation is intentionally conservative: unsupported drags may
   show no preview.
4. **Minimap:** With many columns, drag over both scroll edges, check insertion
   marker, actual new index, Escape/cancel, pinned columns and keyboard focus.
5. **Three-finger:** Compare 33%, 50%, 100% and fixed/oversized columns.
   Note whether a swipe crosses to the neighboring column and capture
   `stripmuxx doctor` after each case. Read the new `Three-finger swipe` line:
   maximum Dock progress, starting column width in viewport units, whether
   the nearest column changed and whether the gesture settled.
6. **Other regressions:** Option+two-finger pan, desktop switching, floating,
   managed/native fullscreen, window restoration, sleep/wake, a second display,
   VoiceOver focus and reduced-motion accessibility.

## Known limitations / explicit constraints

- No automatic physical UI testing was performed by the GitHub connector.
- A native-window drag preview is visual only; the existing post-release
  adoption still authorizes the actual swap.
- Drag hints rely on the focused managed tile, a titlebar-area starting point,
  and the current observed layout. They are skipped rather than guessed.
- Three-finger scrolling motion remains unchanged pending measurements of the
  reported difficulty traversing large columns; the diagnostic line is
  informational, not a fix.
- No AX scheduler rewrite; measure actual slow operations before changing it.

## Release criteria

No XCTest/Python failures, no P0/P1 attributable to the new changes, overlay
removed reliably on release/invalidation, and physical swipe/drag/Space matrix
recorded with explicit pass/fail/untested labels.
