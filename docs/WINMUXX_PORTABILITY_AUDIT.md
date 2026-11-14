# WinMuxX → StripMuxX portability audit (November 2026)

This is an architecture comparison, not a wholesale feature merge. WinMuxX
supports its own workspace abstraction; StripMuxX must continue to use native
macOS Spaces and one scrolling-only strip per Space.

| WinMuxX component | Status in StripMuxX | Decision |
| --- | --- | --- |
| `mouse/DockWorkspaceSwipe.swift` + `WorkspaceGestureCoordinator.swift` | Three-finger Dock swipe tracker adapted in `mouse/StripDockSwipe.swift` | **Ported as opt-in experiment**; preserves unrelated swipes, raw event envelope and startup/wake handling |
| `ui/DockSwipeTrackerTest.swift` | `ui/StripDockSwipeTrackerTest.swift` | **Ported focused tests** for beginning, pass-through, cancellation and native end |
| `runtime/FrameRecovery.swift` | `runtime/NativeFrameRecovery.swift` already has bounded per-tile retries | **Do not duplicate**; the existing native implementation honors scrolling writes and Space ownership |
| `runtime/RuntimeEventRecorder.swift` | Event history + opt-in AX work metrics already exist | **Retain**, improve event-stage diagnostics if a physical performance issue appears |
| `mouse/drag/WindowDragFrameGate.swift` | Mouse-release adoption and native observation already coalesce, but not necessarily pointer velocity | **Candidate** if continuous drag processing causes CPU spikes; test before adding another gate |
| `ui/gestures/WorkspaceMotionDiagnostics.swift` | `nativePanTiming` and scrolling layout timing already exist | **Candidate**: add gesture-to-first-frame latency and count per-display AX writes, not another global timing store |
| `ui/gestures/WorkspaceGestureAnimation.swift` | Scroll viewport already moves immediately, and motion is streamed through AX | **Later**: import only critically damped, interruptible settle math if Reduce Motion is respected and AX write frequency stays bounded |
| `ui/WorkspaceSwipePreview.swift` | Existing scrolling minimap visualizes the strip | **Do not port** workspace preview snapshots/panels; use the minimap rather than a second overlay |
| `ui/sidebar/*`, `tree/Workspace*.swift`, `command/impl/agent/*` | Virtual workspaces, sidebar, projects, agent panes | **Out of scope**; native macOS Spaces are authoritative |
| `layout/DwindleChildFrames.swift` | Horizontal strip with optional vertical stacks only | **Out of scope**; no BSP/dwindle/tabbed mode |

## Experimental three-finger swipe

The source reuses the native macOS Dock swipe events already intercepted by
WinMuxX. This uses undocumented CGEvent fields, **not** public AppKit swipe delivery.
It may break on future macOS releases. It is deliberately **off by default**.

Enable only on a test machine in `~/.config/stripmuxx/stripmuxx.toml`:

```toml
[scrolling]
gesture-enabled = true
three-finger-swipe = true
```

Set macOS Trackpad's horizontal 'Swipe between full-screen applications' to
**three fingers**. StripMuxX claims only horizontal three-finger swipes on an
observed ordinary desktop containing multiple columns. Vertical and unavailable
swipes remain with macOS. Two-finger scrolling and Option + two-finger pan remain
unchanged. Configure only one running window manager to own Dock swipes.

Verification before defaulting on:
1. With another app focused, horizontal three-finger gesture moves columns smoothly in both directions.
2. Two-finger horizontal/vertical scrolling remains inside the frontmost app.
3. A native fullscreen Space, unsupported display, or no scrollable columns leaves the swipe to macOS.
4. Gestures cancelled by Space changes, locking/sleep, and tap timeouts never steal focus.
5. On macOS 27+, the Dock receives the final closure event without space switching.
6. A reconnect or wake re-enables the tap without duplicate interception or stranded gestures.

Do not call this production-proven until tested with a real trackpad, multiple
displays and a new app bundle. The Swift tests cover logic, not Dock event delivery.

## Minimap audit

Current strengths: proportional strip geometry, pinned-column placement, accessible
tiles with keyboard navigation, docked scroll canvas for 40+ columns, native Space
validation on selection/reorder, a non-activating overlay and reduced-motion-aware
dismissal.

Completed this round:
- Redraw an existing tile when its app icon arrives after its initial render.
- Follow a viewport whose mapped position changed after a strip topology/scale change,
  even if the absolute offset did not change.
- Keep the selected tile in view during model refresh while keyboard navigation is active.
- Constrain panel width by actual screen visible-frame width, including narrow screens.
- Expose the minimap and the experimental three-finger setting through Settings search.

Further work, in priority order:
1. Auto-scroll the minimap horizontally when dragging a column near its edges;
   this is essential for reordering across a long strip without dropping.
2. Test minimap drag-and-drop against a Space switch or monitor disconnect
   mid-drag, including the full native window event loop.
3. Reduce title/icon refresh work on large (50+) column strips by prioritizing
   visible tiles and invalidating only modified models.
4. Add an optional explicit "reveal without focusing" interaction for the viewport,
   backed by the existing scrolling-pan command.
5. Physical test of keyboard focus, VoiceOver, hover persistence, high contrast
   and Reduced Motion on light/dark desktop backgrounds.

Keep the minimap a viewport for native Spaces, not a project/sidebar navigator.
