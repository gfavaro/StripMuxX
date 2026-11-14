import AppKit
import Common

extension Workspace {
    /// Lays the strip out: scrolls it to the focused column, places every column and
    /// leaves floating windows where they are.
    @MainActor
    func layoutWorkspace() async throws {
        var pinIndicatorShown = false
        defer { if !pinIndicatorShown { ScrollingPinIndicator.shared.hide(self) } }
        normalizeContainers()
        if isEffectivelyEmpty { return }
        let rect = workspaceTilingRect(self)
        let context = LayoutContext(self)
        lastAppliedLayoutPhysicalRect = rect
        lastAppliedLayoutVirtualRect = rect
        rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
        rootTilingContainer.lastAppliedLayoutVirtualRect = rect
        if let fullscreenWindow = rootTilingContainer.mostRecentWindowRecursive, fullscreenWindow.isFullscreen {
            ScrollingWindowOrdering.shared.cancel()
            WorkspaceScrollingMinimap.shared.dismiss()
            fullscreenWindow.lastAppliedLayoutVirtualRect = rect
            fullscreenWindow.lastAppliedLayoutPhysicalRect = nil
            fullscreenWindow.layoutFullscreen(context)
            return
        }
        try await layoutStrip(in: rect, context)
        ScrollingPinIndicator.shared.update(self, rect: rect, gaps: context.resolvedGaps)
        pinIndicatorShown = true
        // Floating windows keep the frames they have.
        for window in floatingWindows {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
        }
    }
}

@MainActor
private func layoutStrip(in rect: Rect, _ context: LayoutContext) async throws {
    let workspace = context.workspace
    workspace.rebaseScrollingViewportIfNeeded(using: workspace.scrollingMetrics)
    let metrics = workspace.scrollingMetrics
    if !workspace.scrollingGestureMotionActive, let focused = focus.windowOrNil,
       workspace.lastScrollingFocusWindowId != focused.windowId,
       let column = metrics.columns.first(where: { $0.node === focused.topLevelWorkspaceGroup })
    {
        let previous = workspace.lastScrollingFocusWindowId.flatMap(Window.get(byId:)).flatMap { window in
            metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup })
        }
        workspace.scrollingOffset = metrics.focusedOffset(for: column, current: workspace.scrollingOffset,
                                                          previous: previous)
        workspace.lastScrollingFocusWindowId = focused.windowId
    }
    workspace.scrollingOffset = metrics.clampedOffset(workspace.scrollingOffset)
    if !workspace.scrollingGestureMotionActive, let window = focus.windowOrNil as? MacWindow,
       window.nodeWorkspace === workspace,
       let column = metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) {
        let epoch = workspace.scrollingSessionEpoch
        let offsets = (try? await window.scrollingSheetOffsets()) ?? []
        try checkCancellation()
        if workspace.scrollingSessionEpoch == epoch, focus.windowOrNil === window {
            let leafInset = (window.lastAppliedLayoutVirtualRect?.minX ?? 0) -
                (column.node.lastAppliedLayoutVirtualRect?.minX ?? 0)
            let target = offsets.map(\.minX).min().flatMap { left in offsets.map(\.maxX).max().map { right in
                metrics.sheetRevealedOffset(start: column.start + leafInset + left,
                    end: column.start + leafInset + right, current: workspace.scrollingOffset)
            } }
            let step = ScrollingSheetReveal.step(current: workspace.scrollingOffset, windowId: window.windowId,
                target: target, remembered: workspace.scrollingSheetReveal)
            // Stored before the offset so the geometry's range already reaches it.
            workspace.scrollingSheetReveal = step.remembered
            workspace.scrollingOffset = step.remembered == nil ? metrics.clampedOffset(step.offset) : step.offset
        }
    }
    let frames = workspace.columnFrames(in: rect, gaps: context.resolvedGaps)
    let area = workspace.scrollingMetrics.geometry.area
    for frame in frames {
        let concealed = frame.node !== workspace.pinnedScrollingColumn &&
            !CGRect(origin: frame.virtual.topLeftCorner, size: frame.virtual.size).intersects(area)
        for window in frame.node.allLeafWindowsRecursive { window.isConcealedByScrolling = concealed }
        frame.node.layoutColumn(frame.physical, virtual: frame.virtual, context)
    }
    workspace.captureScrollingViewportAnchor()
    ScrollingWindowOrdering.shared.update(workspace: workspace, frames: frames)
}

extension TreeNode {
    /// A column is a window, or a stack whose windows share its height by weight.
    @MainActor
    fileprivate func layoutColumn(_ physical: Rect, virtual: Rect, _ context: LayoutContext) {
        lastAppliedLayoutPhysicalRect = physical
        lastAppliedLayoutVirtualRect = virtual
        switch nodeCases {
            case .window(let window):
                window.isFullscreen = false
                guard !frameRecoveryLeavesAlone(window, tile: physical) else { return }
                let target = windowMotionNativeTarget(CGRect(origin: physical.topLeftCorner, size: physical.size))
                window.setAxFrame(target.origin, target.size)
            case .tilingContainer(let stack):
                let frames = stack.tileChildFrames(in: physical, gaps: context.resolvedGaps)
                let shown = stack.frameLayoutChildren
                // While macOS hides a window of the stack, the frames are a projection: the stored
                // weights still describe every window and stay as they are until all show again.
                let complete = shown.count == stack.children.count
                for (child, frame) in zip(shown, frames) {
                    if complete { child.setWeight(stack.orientation, frame.weight) }
                    let childVirtual = Rect(
                        topLeftX: frame.virtual.topLeftX + virtual.topLeftX - physical.topLeftX,
                        topLeftY: frame.virtual.topLeftY + virtual.topLeftY - physical.topLeftY,
                        width: frame.virtual.width, height: frame.virtual.height)
                    child.layoutColumn(frame.physical, virtual: childVirtual, context)
                }
            case .workspace:
                return
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let rect = fullscreenWindowRect(self, in: context.workspace)
        setAxFrame(rect.topLeftCorner, rect.size)
    }
}

@MainActor
extension TreeNode {
    func minimumLayoutExtent(along axis: Orientation, gaps: ResolvedGaps? = nil) -> CGFloat {
        let gaps = gaps ?? ResolvedGaps(gaps: config.gaps, monitor: nodeMonitor ?? mainMonitor)
        switch nodeCases {
            case .window(let window):
                let minimum = window.minimumLayoutSize
                return axis == .h ? minimum.width : minimum.height
            case .tilingContainer(let container):
                let minimums = container.frameLayoutChildren.map { $0.minimumLayoutExtent(along: axis, gaps: gaps) }
                guard !minimums.isEmpty else { return 0 }
                return container.orientation == axis
                    ? minimums.reduce(0, +) + CGFloat(gaps.inner.get(axis).toDouble()) * CGFloat(minimums.count - 1)
                    : minimums.max() ?? 0
            default: return 0
        }
    }
}
