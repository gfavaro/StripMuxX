import AppKit
import Common
import PrivateApi

final class MacWindow: Window {
    let macApp: MacApp
    @MainActor override var minimumLayoutSize: CGSize { learnedMinimum.size }

    @MainActor private(set) var learnedMinimum = LearnedWindowMinimum()
    @MainActor private var minimumObservation: Task<Void, Never>?
    @MainActor private var frameRequestGeneration: UInt64 = 0
    @MainActor private var minimumRequest: (point: CGPoint?, size: CGSize?)?
    @MainActor private var scrollingSheetCache: (generation: UInt64, offsets: [CGRect])?

    @MainActor func invalidateScrollingSheetCache() { scrollingSheetCache = nil }

    @MainActor
    func scrollingSheetOffsets() async throws -> [CGRect] {
        let generation = nativeStateObservationToken()
        if let cache = scrollingSheetCache, cache.generation == generation { return cache.offsets }
        let offsets = try await macApp.attachedSheetOffsets(windowId)
        guard nativeStateObservationToken() == generation else { return [] }
        scrollingSheetCache = (generation, offsets)
        return offsets
    }

    @MainActor
    func resetLearnedMinimum() {
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        minimumObservation = nil
        minimumRequest = nil
        learnedMinimum = LearnedWindowMinimum()
    }

    @MainActor
    func forgetProvisionalMinimumEvidence() { learnedMinimum.forgetProvisionalEvidence() }

    @MainActor
    func restoreLearnedMinimum(_ size: CGSize?, savedBundleId: String?, generation: MinimumEvidenceGeneration) {
        guard let size, size.width.isFinite, size.height.isFinite,
              size.width >= 0, size.height >= 0, size != .zero,
              PersistedAppMinimums.shared.acceptsEvidence(generation, for: macApp.rawAppBundleId,
                                                           savedBundleId: savedBundleId) else { return }
        learnedMinimum = LearnedWindowMinimum(size: size)
    }
    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        if !isUnitTest, let size = PersistedAppMinimums.shared.size(for: actor.rawAppBundleId) {
            learnedMinimum = LearnedWindowMinimum(size: size)
        }
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    /// Adopts a window macOS reports on a showing desktop, or returns nil when its
    /// Space, process or native state rules it out.
    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        try await getOrRegisterNative(windowId: windowId, macApp: macApp)
    }

    @MainActor
    private static func getOrRegisterNative(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        let layouts = runtime.native.layouts
        guard let registration = layouts.registration(for: windowId),
              !macApp.nsApp.isTerminated else { return nil }
        let workspace = registration.workspace
        if let existing = allWindowsMap[windowId], existing.macApp === macApp,
           existing.nodeWorkspace === workspace {
            let native = try await macApp.readNativeState(windowId)
            try Task.checkCancellation()
            guard layouts.accepts(registration) else { return nil }
            existing.nativeLayoutEligible = native?.fullscreen == false && native?.minimized == false
            return existing.nativeLayoutEligible ? existing : nil
        }
        let rect = try await macApp.getAxRect(windowId)
        let type = try await macApp.getAxUiElementWindowType(windowId, getWindowLevel(for: windowId))
        let native = try await macApp.readNativeState(windowId)
        try Task.checkCancellation()
        guard layouts.accepts(registration),
              !macApp.nsApp.isTerminated, native?.fullscreen == false, native?.minimized == false else { return nil }
        if case .popup = type { return nil }
        if let existing = allWindowsMap[windowId] {
            if existing.macApp !== macApp {
                existing.garbageCollect()
            } else {
                let floated = existing.parent is Workspace
                let binding = floated ? BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                    : bindingDataForNewWindow(type: type, workspace: workspace, window: existing)
                existing.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                existing.recordAuthoritativeActualRect(rect)
                return existing
            }
        }
        let binding = bindingDataForNewWindow(type: type, workspace: workspace, window: nil)
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size,
            parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        window.recordAuthoritativeActualRect(rect)
        allWindowsMap[windowId] = window
        window.restartIdentity = try? await macApp.getRestartWindowIdentity(windowId)
        applyLayoutForNextDetectedWindow(window, on: workspace)
        try await applyNativeWindowDetectedRules(window) { layouts.accepts(registration) }
        runtime.native.stateChanges.notify() // Wakes a palette pick awaiting adoption.
        runtime.native.tiling.windowAdopted(window)
        return window
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel)
    }

    func dumpAxInfo() async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId)
    }

    @MainActor
    override func readNativeState() async throws -> (fullscreen: Bool, minimized: Bool)? {
        do { return try await macApp.readNativeState(windowId) }
        catch let failure as AXReadFailure where failure.code == .cannotComplete { return nil }
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    @MainActor
    func garbageCollect() {
        guard MacWindow.allWindowsMap.removeValue(forKey: windowId) != nil else { return }
        resetLearnedMinimum()
        if parent != nil { _ = unbindFromParent() }
    }

    @MainActor override var title: String { get async throws { try await macApp.getAxTitle(windowId) ?? "" } }
    @MainActor override var isMacosFullscreen: Bool { get async throws { try await macApp.isMacosNativeFullscreen(windowId) == true } }
    @MainActor override var isMacosMinimized: Bool { get async throws { try await macApp.isMacosNativeMinimized(windowId) == true } }

    @MainActor
    override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect()
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    override func getAxSize() async throws -> CGSize? {
        try await macApp.getAxSize(windowId)
    }

    @MainActor
    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        NativeFrameWriteMetrics.shared.requests &+= 1
        if nodeWorkspace?.scrollingGestureMotionActive == true, let session = nodeWorkspace?.scrollingGestureSessionID,
           let topLeft, let size {
            NativeFrameWriteMetrics.shared.gestureRequests &+= 1
            setScrollingGestureFrame(CGRect(origin: topLeft, size: size), session: session)
            return
        }
        NativeFrameWriteMetrics.shared.normalRequests &+= 1
        NativeOriginalFrames.shared.recordBeforeWrite(self)
        macApp.setAxFrame(windowId, topLeft, size)
        // Reasserting an unchanged layout must neither flood AX with observations nor
        // continually cancel the confirmation already waiting for that same request.
        if let previous = minimumRequest, previous.point == topLeft, previous.size == size {
            NativeFrameWriteMetrics.shared.repeatedTargets &+= 1
            return
        }
        minimumRequest = (topLeft, size)
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        guard let topLeft, let size, parent is TilingContainer, !isFullscreen,
              !isConcealedByScrolling,
              TrayMenuModel.shared.isEnabled, lastKnownActualRect?.size != size else { return }
        let generation = frameRequestGeneration
        minimumObservation = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let self, self.canObserveMinimum(generation) else { return }
                let fullscreen = try await self.isMacosFullscreen
                let minimized = try await self.isMacosMinimized
                guard shouldLearnWindowMinimum(nativeFullscreen: fullscreen, nativeMinimized: minimized),
                      let first = try await self.macApp.getAxRectForLayoutConfirmation(self.windowId) else { return }
                try await Task.sleep(nanoseconds: 150_000_000)
                guard self.canObserveMinimum(generation),
                      let confirmed = try await self.macApp.getAxRectForLayoutConfirmation(self.windowId),
                      self.canObserveMinimum(generation),
                      abs(first.topLeftCorner.x - topLeft.x) <= 2,
                      abs(first.topLeftCorner.y - topLeft.y) <= 2,
                      abs(confirmed.topLeftCorner.x - topLeft.x) <= 2,
                      abs(confirmed.topLeftCorner.y - topLeft.y) <= 2 else { return }
                // Native fullscreen/minimize can start between the two samples.
                let confirmedFullscreen = try await self.isMacosFullscreen
                let confirmedMinimized = try await self.isMacosMinimized
                guard self.canObserveMinimum(generation),
                      shouldLearnWindowMinimum(nativeFullscreen: confirmedFullscreen, nativeMinimized: confirmedMinimized) else { return }
                let oldMinimum = self.learnedMinimum.size
                self.learnedMinimum.observe(requested: size, first: first.size, confirmed: confirmed.size)
                if self.learnedMinimum.size != oldMinimum {
                    runtime.native.observation?.requestRead(event: "nativeMinimumChanged")
                }
                if !isUnitTest { PersistedAppMinimums.shared.remember(self.learnedMinimum.size, for: self.macApp.rawAppBundleId) }
            } catch {
                // Cancellation, closed windows and failed AX reads are not minimum-size evidence.
            }
        }
    }

    @MainActor
    func setScrollingGestureFrame(_ frame: CGRect, session: UUID? = nil) {
        guard let workspace = nodeWorkspace, workspace.scrollingGestureMotionActive,
              let session = session ?? workspace.scrollingGestureSessionID else { return }
        suspendMinimumObservationForMotion()
        NativeOriginalFrames.shared.recordBeforeWrite(self)
        macApp.setAnimatedAxFrame(windowId, frame, session: session)
    }

    @MainActor
    private func canObserveMinimum(_ generation: UInt64) -> Bool {
        !Task.isCancelled && frameRequestGeneration == generation &&
            MacWindow.allWindowsMap[windowId] === self && parent is TilingContainer &&
            !isFullscreen && TrayMenuModel.shared.isEnabled &&
            !isConcealedByScrolling && nodeWorkspace?.scrollingGestureMotionActive != true
    }

    @MainActor
    func suspendMinimumObservationForMotion() {
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        minimumObservation = nil
        minimumRequest = nil
    }

    @MainActor
    override func getAxRect() async throws -> Rect? {
        let observationToken = await nativeStateObservationToken()
        let rect = try await macApp.getAxRect(windowId)
        let windowId = self.windowId
        await MainActor.run {
            Window.get(byId: windowId)?.recordObservedActualRect(rect, token: observationToken)
        }
        return rect
    }
}
