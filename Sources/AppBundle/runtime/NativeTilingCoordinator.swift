import AppKit
import Common
import NativeSpaces

enum NativeTilingCommandScope {
    @TaskLocal static var active = false
    /// `move --boundaries all-monitors-outer-frame` past a display edge: the window
    /// leaves the fenced desktop, so the native move runs after the command. Each
    /// fenced run has its own sink, so overlapping commands never share it.
    @TaskLocal static var monitorMoveSink: MonitorMoveSink?

    @MainActor final class MonitorMoveSink {
        var pending: MoveNodeToMonitorCmdArgs?
    }
    @TaskLocal static var validateTarget: (@MainActor @Sendable () -> Bool)?
}

/// Applies the shared engine to observed active desktop trees. It neither owns
/// Spaces nor uses virtual activation, parking, recovery or layout algorithms.
@MainActor
final class NativeTilingCoordinator {
    private(set) var status = "Observation only" {
        didSet { if status != oldValue { isStopped = false; updateTrayText() } }
    }
    /// Tiling stays off until something outside StripMuxX changes; the tray marks it.
    private(set) var isStopped = false
    private(set) var ready = false {
        didSet { if ready, !oldValue { runtime.native.stateChanges.notify() } }
    }
    /// Set by the first completed layout; windows registered before it existed at startup.
    private(set) var hasCompletedInitialLayout = false
    private var hasManagedNativeFocus = false
    private var generation: UInt64 = 0
    private var shortcutsInstalled = false
    private var mouseMonitor: Any?
    private let dragPreview = NativeWindowDragPreview()

    /// Tests stand in for an accepted observation of the desktops they set up.
    func assumeReconciledForTests() {
        precondition(isUnitTest)
        ready = true
        hasManagedNativeFocus = true
        hasCompletedInitialLayout = true
    }

    func invalidate(_ reason: String = "other") {
        // A native Space/window lifecycle change can invalidate the drag's
        // identity even while the mouse is down. Do not leave overlay panels
        // on a different Space after that transition.
        dragPreview.hide()
        nativePanTiming.count("invalidate: \(reason)")
        generation &+= 1
        ready = false
        hasManagedNativeFocus = false
        status = "Waiting for native reconciliation"
        for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
    }

    private func stopTiling(_ reason: String) {
        status = reason
        isStopped = true
        updateTrayText()
    }

    func stop() {
        scrollingPersistenceTask?.cancel()
        scrollingPersistenceTask = nil
        invalidate()
        MacApp.cancelPendingFocus()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        dragPreview.hide()
    }

    func accept(_ snapshot: NativeSpacesSnapshot, identities: [NativeWindowWriteIdentity]) async {
        let acceptStart = ContinuousClock.now
        defer { nativePanTiming.record("accept (after read)", acceptStart.duration(to: .now)) }
        guard !serverArgs.isReadOnly else { stopTiling("Tiling suppressed by read-only startup"); return }
        guard TrayMenuModel.shared.isEnabled else { status = "Tiling disabled (enable on resumes it)"; return }
        guard AXIsProcessTrusted(), runtime.native.observation?.windowEventsAvailable == true else {
            stopTiling("Tiling suspended: Accessibility or native lifecycle events unavailable")
            return
        }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            stopTiling("Tiling suspended: Mission Control observation is not validated on this macOS version")
            return
        }
        let version = generation
        let screenSizes = monitors.map { $0.rect.size }
        let missionControl = await Task.detached {
            guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return true }
            return NativeSpaceTransitionGuard.isMissionControlVisible(rows, screenSizes: screenSizes) { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        }.value
        guard generation == version else { return }
        guard !missionControl, NSEvent.pressedMouseButtons == 0, !holdsForMouseRelease else {
            status = missionControl ? "Tiling paused for Mission Control" : "Tiling paused for mouse interaction"
            return
        }
        guard snapshot.displays.contains(where: { runtime.native.layouts.activeWorkspace(on: $0.identifier) != nil }) else {
            // One shared set of desktops across displays is reported as "Main"; native
            // tiling lays out per display, so it says why instead of doing nothing.
            if snapshot.displays.contains(where: { $0.identifier == "Main" }) {
                stopTiling("Tiling unavailable: turn on Displays have separate Spaces (System Settings › Desktop & Dock)")
            } else {
                status = "Tiling paused: no active ordinary desktop"
            }
            return
        }
        await runtime.native.persistence.reconcile(runtime.native.layouts)
        guard generation == version else { return }
        runtime.native.writeAuthority.replace(snapshot: snapshot, identities: identities)
        await synchronizeFocus()
        guard generation == version else { return }
        runtime.native.noteNativeActivity()
        if mouseMonitor == nil && !isUnitTest {
            let owner = runtime
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak owner] event in
                let released = event.type == .leftMouseUp || event.type == .rightMouseUp
                let leftButton = event.type == .leftMouseDown || event.type == .leftMouseUp
                Task { @MainActor [weak owner] in
                    guard let owner else { return }
                    owner.withValue {
                        MacApp.cancelPendingFocus()
                        if !released { owner.native.focusHold.end() } // A click elsewhere is the user's.
                        let tiling = owner.native.tiling
                        if released { tiling.dragPreview.hide() }
                        else if leftButton { tiling.dragPreview.begin(at: mouseLocation) }
                        guard released else {
                            // A read queued by the drag's own move events must not lay the
                            // window back out before its release is adopted.
                            if leftButton { tiling.holdsForMouseRelease = true }
                            return owner.native.writeAuthority.invalidate()
                        }
                        owner.task {
                            if leftButton { await tiling.adoptMouseRelease() }
                            tiling.holdsForMouseRelease = false
                            owner.native.observation?.requestRead(event: "nativeMouseReleased")
                        }
                    }
                }
            }
        }
         if !shortcutsInstalled {
            shortcutsInstalled = true
            try? await activateMode(mainModeId, runCallbacks: false)
        }
        guard !holdsForMouseRelease else { status = "Tiling paused for mouse interaction"; return }
        let targets = Set(snapshot.reconciliationSpaceIDs ?? snapshot.displays.map(\.activeSpaceID))
        for display in snapshot.displays where targets.contains(display.activeSpaceID) {
            guard generation == version,
                  let workspace = runtime.native.layouts.activeWorkspace(on: display.identifier) else { continue }
            do { try await workspace.layoutWorkspace() }
            catch { stopTiling("Native layout suspended: \(error)"); runtime.native.writeAuthority.invalidate(); ready = false; return }
            guard generation == version else { return }
        }
        await runtime.native.persistence.save(runtime.native.layouts)
        guard generation == version else { return }
        ready = true
        hasCompletedInitialLayout = true
        if scrollingReadRequestedAt != nil { scrollingReadRequestedAt = nil; relayoutVisibleScrolling() }
        status = "Native tiling active"
    }

    /// Reads the frontmost window once its drag has ended and adopts a resize or a
    /// drop onto another tile; the read that follows lays the desktop out again.
    func adoptMouseRelease() async {
        guard hasCompletedInitialLayout else { return lastMouseRelease = "ignored: no completed native layout yet" }
        guard let front = NSWorkspace.shared.frontmostApplication, let app = try? await MacApp.getOrRegister(front),
              let window = try? await app.getFocusedWindow() else {
            return lastMouseRelease = "ignored: frontmost window is not managed"
        }
        guard let actual = try? await window.getAxRect() else { return lastMouseRelease = "ignored: window \(window.windowId) frame unreadable" }
        let target = window.lastAppliedLayoutPhysicalRect.map { "\($0)" } ?? "none"
        let outcome = adoptNativeMouseRelease(window, actual: actual, pointer: mouseLocation)
        lastMouseRelease = "window \(window.windowId): \(outcome); actual \(actual), layout \(target)"
    }

    private var scrollingLayoutTask: Task<Void, Never>?
    private var scrollingPersistenceTask: Task<Void, Never>?
    private var scrollingLayoutPending = false
    private var scrollingLayoutRequests = ScrollingRelayoutSelection()

    /// A gesture on one display should not issue AX writes to every other display.
    /// No target requests every visible desktop (e.g. after a fresh observation).
    /// Requests made while a layout is running are coalesced, not discarded.
    func relayoutVisibleScrolling(target: Workspace? = nil) {
        nativePanTiming.count("relayout requested")
        guard ready else {
            nativePanTiming.count("relayout skipped: not ready")
            // Every read starts by invalidating, so a read per scroll step would keep
            // tiling unready for the whole pan. Ask once; accept() lays out after it.
            if let asked = scrollingReadRequestedAt, asked.duration(to: .now) < .milliseconds(250) { return }
            scrollingReadRequestedAt = .now
            return runtime.native.observation?.requestRead(event: "nativeScrolling") ?? ()
        }
        scrollingLayoutRequests.request(target)
        if scrollingLayoutTask != nil { scrollingLayoutPending = true; return }
        scrollingLayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                scrollingLayoutPending = false
                let selection = scrollingLayoutRequests.drain()
                let version = generation
                for workspace in runtime.native.layouts.currentBySpaceID.values
                    where workspace.isVisible && selection.includes(workspace) {
                    guard ready, generation == version, !holdsForMouseRelease else {
                        nativePanTiming.count("relayout aborted: \(!ready ? "not ready" : generation != version ? "generation" : "mouse")")
                        break
                    }
                    let start = ContinuousClock.now
                    do { try await workspace.layoutWorkspace() } catch { break }
                    nativePanTiming.record("scrolling layout", start.duration(to: .now))
                    noteScrollingLayout(start.duration(to: .now), during: workspace.scrollingGestureMotionActive)
                }
            } while scrollingLayoutPending
            scrollingLayoutTask = nil
            // Scrolling, column reordering and resizing bypass accept(), which
            // is otherwise the only place that persists a desktop layout.
            // Debounce disk writes while the fingers are moving, but record the
            // final strip once a layout settles. Stale runs never save another Space.
            scheduleScrollingPersistence()
        }
    }

    /// Writes a strip change still waiting out the save debounce. Quitting and
    /// `enable off` invalidate tiling, which would otherwise drop it unsaved.
    func flushPendingScrollingPersistence() async {
        guard let pending = scrollingPersistenceTask else { return }
        pending.cancel()
        scrollingPersistenceTask = nil
        await runtime.native.persistence.save(runtime.native.layouts)
    }

    private func scheduleScrollingPersistence() {
        scrollingPersistenceTask?.cancel()
        let version = generation
        scrollingPersistenceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, !Task.isCancelled, self.ready, self.generation == version,
                  !self.holdsForMouseRelease else { return }
            await runtime.native.persistence.save(runtime.native.layouts)
            self.scrollingPersistenceTask = nil
        }
    }

    private var scrollingReadRequestedAt: ContinuousClock.Instant?

    /// Layout timings of the current or last pan, for doctor: running totals only.
    private var panLayouts = (count: 0, totalMs: 0.0, maxMs: 0.0)
    private var panStarted: ContinuousClock.Instant?
    private var panLast: ContinuousClock.Instant?

    var scrollingLayoutTiming: String {
        guard panLayouts.count > 0, let panStarted, let panLast else { return "none" }
        let span = panStarted.duration(to: panLast).components
        let seconds = max(0.001, Double(span.seconds) + Double(span.attoseconds) / 1e18)
        return String(format: "%d layouts, %.0f/s, avg %.1f ms, max %.1f ms", panLayouts.count,
            Double(panLayouts.count) / seconds, panLayouts.totalMs / Double(panLayouts.count), panLayouts.maxMs)
    }

    private func noteScrollingLayout(_ duration: Duration, during gesture: Bool) {
        guard gesture else { panStarted = nil; return }
        let now = ContinuousClock.now
        if panStarted == nil { panStarted = now; panLayouts = (0, 0, 0) }
        panLast = now
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        panLayouts = (panLayouts.count + 1, panLayouts.totalMs + ms, max(panLayouts.maxMs, ms))
    }

    /// Waits for the read in progress to be accepted and tiling to be ready again.
    func waitUntilReady(timeout: Duration = .milliseconds(1500)) async -> Bool {
        await runtime.native.stateChanges.wait(timeout: timeout) { ready }
    }

    /// Set at left mouse-down; layout waits until that drag's release is adopted.
    var holdsForMouseRelease = false

    /// The last release decision, for doctor.
    private(set) var lastMouseRelease = "none"

    /// The first read after launch can come before the frontmost app's windows are
    /// adopted, leaving no focus until an unrelated event; adopting its window syncs then.
    func windowAdopted(_ window: Window) {
        guard ready, !hasManagedNativeFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.pid else { return }
        Task { @MainActor in await synchronizeFocus() }
    }

    func synchronizeFocus() async {
        hasManagedNativeFocus = false
        if let front = NSWorkspace.shared.frontmostApplication,
           let app = try? await MacApp.getOrRegister(front),
           let window = try? await app.getFocusedWindow(), window.nativeLayoutEligible,
           runtime.native.layouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace,
           !nativeFocusHoldRejects(window) {
            _ = window.focusWindow()
            runtime.nativeFocus.lastKnownWindowID = window.windowId
            hasManagedNativeFocus = true
            return
        }
        // An empty desktop still has a layout target; it must not activate an app.
        if let workspace = runtime.focus.requested.liveOrNil?.workspace,
           runtime.native.layouts.currentBySpaceID.values.contains(where: { $0 === workspace }),
           workspace.isVisible { return }
        if let display = runtime.native.layouts.snapshot?.displays.first,
           let workspace = runtime.native.layouts.activeWorkspace(on: display.identifier) {
            _ = setFocus(to: workspace.toLiveFocus(), origin: .native)
        }
    }

    static func supports(_ command: any Command) -> Bool {
        switch command {
            case is DoctorCommand, is ReloadConfigCommand, is ModeCommand,
                 is ResizeCommand, is SwapCommand,
                 // Per-window actions; observation reconciles the states they produce.
                 is FullscreenCommand, is MacosNativeFullscreenCommand, is MacosNativeMinimizeCommand,
                 is CloseCommand, is CloseAllWindowsButCurrentCommand,
                 is BalanceSizesCommand, is JoinWithCommand,
                 is ScrollingCenterCommand, is ScrollingWidthCommand, is ScrollingWidthPixelsCommand,
                 is ScrollingPanCommand, is ScrollingMinimapCommand,
                 is ScrollingFocusCommand, is ScrollingMoveCommand, is ScrollingPinCommand,
                 is UndoLayoutCommand, is RetileCommand: return true
            case is FlattenWorkspaceTreeCommand: return true
            case is MoveCommand: return true
            case let command as FocusCommand:
                return command.args.boundaries == .workspace && command.args.boundariesAction != .wrapAroundAllMonitors
            case let command as LayoutCommand:
                return !command.args.forNextDetectedWindow && command.args.toggleBetween.val.allSatisfy {
                    $0 == .tiling || $0 == .floating
                }
            default: return false
        }
    }

    func run(_ commands: [any Command], env: CmdEnv, io: CmdIo) async throws -> Bool {
        guard commands.allSatisfy(Self.supports) else { return io.err("Operation unsupported by the native tiling MVP") }
        guard let target = NativeCommandTargetFence(commands, env: env,
            defaultFocus: runtime.focus.requested.liveOrNil, layouts: runtime.native.layouts) else {
            return io.err("Native command target is not an observed active desktop")
        }
        runtime.native.observation?.requestRead(event: "nativeCommand")
        // Bounded readiness wait, with no additional native queries. Reconciliation
        // is owned by the event pipeline; newer events can supersede it safely.
        _ = await runtime.native.stateChanges.wait(timeout: .seconds(5)) {
            if case .unavailable = runtime.native.observation?.inventory.status { return true }
            return ready
        }
        try Task.checkCancellation()
        guard ready else { return io.err("Native tiling is not ready: \(status)") }
        guard target.matches(runtime.native.layouts, defaultFocus: runtime.focus.requested.liveOrNil) else {
            return io.err("Native command cancelled because its target changed during reconciliation")
        }
        guard hasManagedNativeFocus || commands.allSatisfy({
            $0 is DoctorCommand || $0 is ReloadConfigCommand || $0 is ModeCommand || $0 is RetileCommand ||
                $0.args.windowId != nil || env.windowId != nil
        }) else { return io.err("The frontmost window is not managed by native tiling; use an eligible explicit --window-id") }
        let validate: @MainActor @Sendable () -> Bool = {
            target.matches(runtime.native.layouts,
                defaultFocus: runtime.focus.requested.liveOrNil, allowDefaultFocusChanges: true)
        }
        let sink = NativeTilingCommandScope.MonitorMoveSink()
        let result = try await NativeTilingCommandScope.$validateTarget.withValue(validate) {
            try await NativeTilingCommandScope.$monitorMoveSink.withValue(sink) {
                try await NativeTilingCommandScope.$active.withValue(true) {
                    try await commands.runCmdSeq(env, io)
                }
            }
        }
        let monitorMove = sink.pending
        if result {
            // Closing removes the target on purpose; its absence is success, not a race.
            let closesTarget = commands.allSatisfy { $0 is CloseCommand || $0 is CloseAllWindowsButCurrentCommand }
            guard closesTarget || validate() else { return io.err("Native command target changed before completion") }
            if let monitorMove {
                return await runtime.native.windowMoves.transferWindow(monitorMove, env: env, io: io)
            }
            if commands.contains(where: { $0 is FocusCommand || $0 is ScrollingFocusCommand }) {
                focus.windowOrNil?.nativeFocus()
            } else {
                runtime.native.observation?.requestRead(event: "nativeCommandCompleted")
            }
        }
        return result
    }
}

/// Coalesces per-workspace scrolling requests; an unscoped refresh supersedes
/// narrower requests. IDs do not retain Workspaces across Space reconciliation.
struct ScrollingRelayoutSelection {
    private var all = false
    private var targets = Set<ObjectIdentifier>()

    mutating func request(_ workspace: Workspace?) {
        guard let workspace else { all = true; targets.removeAll(); return }
        if !all { targets.insert(ObjectIdentifier(workspace)) }
    }

    mutating func drain() -> Batch {
        let batch = Batch(all: all, targets: targets)
        all = false
        targets.removeAll()
        return batch
    }

    struct Batch {
        let all: Bool
        let targets: Set<ObjectIdentifier>
        func includes(_ workspace: Workspace) -> Bool {
            all || targets.contains(ObjectIdentifier(workspace))
        }
    }
}
