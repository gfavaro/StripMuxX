import AppKit
import Common

open class Window: TreeNode, Hashable {
    let windowId: UInt32
    let app: any AbstractApp
    var nativeLayoutEligible = true
    var restartIdentity: RestartWindowIdentity?
    /// Its column is scrolled out of the strip's viewport.
    @MainActor private var scrollingColumnConcealed = false
    @MainActor var isConcealedByScrolling: Bool {
        get { scrollingColumnConcealed && parent is TilingContainer }
        set { scrollingColumnConcealed = newValue }
    }
    var lastFloatingSize: CGSize?
    /// Explicit strip member whose natural size and vertical offset are preserved.
    /// Unlike floating, it remains a column in the workspace tiling container.
    @MainActor var freeSizeRect: Rect?
    @MainActor var freeSizePreviousColumnWidth: CGFloat?
    @MainActor var freeSizePreviousFixedWidth: CGFloat?
    /// Floated with `layout floating`. Other floating windows join the strip at their own size.
    @MainActor var keptFloating = false
    // Width chosen by the user for a lone tile on ultrawide, persisted with its layout.
    var singleWindowManualWidth: CGFloat?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    /// Event-invalidated caches of the native window state (frame, fullscreen, minimized),
    /// read on hot paths instead of polling every window over AX. Entering/exiting native
    /// fullscreen always resizes the window (invalidated via moved/resized events); minimize
    /// state changes emit miniaturized/deminiaturized events. nil means "no observation since
    /// the last event" and readers must fetch live.
    ///
    /// Writes go through the record methods below: an async AX observation races the very
    /// events that invalidate these caches, and a stale value written back after the
    /// transition's events were consumed would look valid forever (nothing would invalidate
    /// it again). Observed values are therefore discarded unless the generation captured
    /// before the fetch is still current.
    @MainActor private(set) var lastKnownActualRect: Rect? = nil
    @MainActor private(set) var lastKnownNativeFullscreen: Bool? = nil
    @MainActor private(set) var lastKnownNativeMinimized: Bool? = nil
    @MainActor private var lastKnownNativeStateGeneration: UInt64 = 0

    @MainActor
    func invalidateLastKnownNativeState() {
        lastKnownNativeStateGeneration += 1
        lastKnownActualRect = nil
        lastKnownNativeFullscreen = nil
        lastKnownNativeMinimized = nil
    }

    /// Capture before starting an async AX observation and pass to the matching record method.
    @MainActor
    func nativeStateObservationToken() -> UInt64 { lastKnownNativeStateGeneration }

    @MainActor
    func recordObservedActualRect(_ rect: Rect?, token: UInt64) {
        if lastKnownNativeStateGeneration == token {
            lastKnownActualRect = rect
            runtime.events.record(.nativeFrameObserved, source: .nativeState, generation: token, windowID: windowId, observedFrame: rect)
        } else {
            runtime.events.record(.staleObservation, source: .nativeState, generation: token, windowID: windowId)
        }
    }

    @MainActor
    func recordObservedNativeState(fullscreen: Bool, minimized: Bool, token: UInt64) {
        if lastKnownNativeStateGeneration == token {
            lastKnownNativeFullscreen = fullscreen
            lastKnownNativeMinimized = minimized
        } else {
            runtime.events.record(.staleObservation, source: .nativeState, generation: token, windowID: windowId)
        }
    }

    /// For writers that know the current frame because they just set or saved it themselves
    /// (interaction-opacity parking/restore, initial registration). Supersedes any in-flight
    /// observation so a slow fetch can't clobber the deliberately written value.
    @MainActor
    func recordAuthoritativeActualRect(_ rect: Rect?) {
        lastKnownNativeStateGeneration += 1
        lastKnownActualRect = rect
        runtime.events.record(.nativeFrameWritten, source: .model, generation: lastKnownNativeStateGeneration, windowID: windowId, intendedFrame: rect)
    }

    @MainActor
    func readNativeState() async throws -> (fullscreen: Bool, minimized: Bool)? {
        let fullscreen = try await isMacosFullscreen
        let minimized = try await (!fullscreen).andAsync { @MainActor @Sendable in try await self.isMacosMinimized }
        return (fullscreen, minimized)
    }

    @MainActor var minimumLayoutSize: CGSize { .zero }

    @MainActor
    init(id: UInt32, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static func get(byId windowId: UInt32) -> Window? { // todo make non optional
        isUnitTest
            ? Workspace.all.flatMap { $0.allLeafWindowsRecursive }.first(where: { $0.windowId == windowId })
            : MacWindow.allWindowsMap[windowId]
    }

    @MainActor
    func closeAxWindow() { die("Not implemented") }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    func getAxSize() async throws -> CGSize? { die("Not implemented") }
    var title: String { get async throws { die("Not implemented") } }
    var isMacosFullscreen: Bool { get async throws { false } }
    var isMacosMinimized: Bool { get async throws { false } } // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    @MainActor
    func nativeFocus() { die("Not implemented") }
    func getAxRect() async throws -> Rect? { die("Not implemented") }
    func getCenter() async throws -> CGPoint? { try await getAxRect()?.center }

    @MainActor
    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
}

extension Window {
    var isFloating: Bool { parent is Workspace } // todo drop. It will be a source of bugs when sticky is introduced

    @discardableResult
    @MainActor
    func bindAsFloatingWindow(to workspace: Workspace) -> BindingData? {
        bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
