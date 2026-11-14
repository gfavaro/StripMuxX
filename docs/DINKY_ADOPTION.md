# Dinky comparison and deliberate StripMuxX adoption

Source studied: https://github.com/mikker/Dinky (`Sources/DinkyLayout/Scrolling.swift`, `FrameScheduler.swift`, `FrameWrites.swift`, `Sources/dinky/FrameApplier.swift`, `DragPlaceholders.swift`, `Swipe.swift`)

## Adopted

- Independent `lone-window-width` and `fullscreen-width` globally and per display; existing configurations retain the legacy fallback when the new key is absent.
- Individual independent Settings controls and width configuration documentation.

## Already present in StripMuxX

- Horizontal strip with focused-window reveal, edge parking and display walls.
- Per-app AX scheduling, coalesced native tiling, generation-based authority for native writes and recovery of frames.
- Native Space observation and guarded transitions.
- Direct tracking of three-finger gesture motion, validated on actual hardware; do not replace it with Dinky's step-based gesture handler.

## Not copied without further validation

- Dinky's full `FrameScheduler`: duplicating AX queues can reorder or invalidate StripMuxX's write authority guarantees. Benchmark diagnostics already record request counts; compare actual read/write metrics before further changes.
- Dinky's drag placeholders: StripMuxX currently pauses layout while the mouse is held and adopts the result on release. A reliable placeholder requires identification of the *dragged* window independent of keyboard focus, verified coordinate conversion across monitors, and guaranteed cancellation on Space switching. A focused-window guess is not safe.
- Spring animations: would increase WindowServer/AX traffic on the validated smooth gesture path.

## Next validation

- `make check` on macOS.
- Test a custom config with only `fullscreen-width = 0.7`, then one with `lone-window-width = 0.6` and `fullscreen-width = 1`.
- Test per-display fallback on an ultrawide and a laptop screen.
- Collect frame request counters from `stripmuxx doctor` across a 10-second gesture and while resizing a window.
