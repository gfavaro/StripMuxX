import AppKit

struct ScrollingMinimapGeometry {
    let tiles: [CGRect]
    let viewport: CGRect
    let bounds: CGRect

    init(metrics: ScrollingWorkspaceMetrics, offset: CGFloat, bounds: CGRect) {
        self.bounds = bounds
        let start = metrics.offsetRange.lowerBound
        let end = max(metrics.totalWidth, metrics.offsetRange.upperBound + metrics.areaWidth)
        let span = max(end - start, 1)
        let scale = min(max(bounds.width, 0) / span, max(bounds.height, 0) / max(metrics.geometry.area.height, 1))
        let originX = bounds.midX - span * scale / 2
        let height = metrics.geometry.area.height * scale
        let originY = bounds.midY - height / 2
        tiles = metrics.columns.map { column in
            CGRect(x: originX + (column.start - start) * scale, y: originY,
                   width: column.width * scale, height: height)
        }
        viewport = CGRect(x: originX + (metrics.clampedOffset(offset) - start) * scale,
                          y: originY, width: metrics.areaWidth * scale, height: height)
    }

    /// Gaps and narrow tiles remain selectable across the entire map strip.
    func column(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return tiles.indices.min { lhs, rhs in
            func distance(_ frame: CGRect) -> CGFloat { max(frame.minX - point.x, point.x - frame.maxX, 0) }
            let a = distance(tiles[lhs]), b = distance(tiles[rhs])
            return a == b ? abs(tiles[lhs].midX - point.x) < abs(tiles[rhs].midX - point.x) : a < b
        }
    }
}

/// The same scale applies to both axes. Grow the row for unusually narrow
/// columns to retain 32-point targets without stretching their window shapes.
func scrollingMinimapRowHeight(metrics: ScrollingWorkspaceMetrics, preferredHeight: CGFloat = 58,
                               minimumTileWidth: CGFloat = 32) -> CGFloat {
    guard let narrowest = metrics.columns.map(\.width).min() else { return preferredHeight }
    return max(preferredHeight, ceil(minimumTileWidth * max(metrics.geometry.area.height, 1) / max(narrowest, 1)))
}

func scrollingMinimapContentWidth(metrics: ScrollingWorkspaceMetrics, visibleWidth: CGFloat,
                                  minimumTileWidth: CGFloat = 32) -> CGFloat {
    let start = metrics.offsetRange.lowerBound
    let end = max(metrics.totalWidth, metrics.offsetRange.upperBound + metrics.areaWidth)
    let scale = scrollingMinimapRowHeight(metrics: metrics, minimumTileWidth: minimumTileWidth) / max(metrics.geometry.area.height, 1)
    return max(visibleWidth, max(end - start, 1) * scale)
}

/// Scroll one small step per drag event near a minimap edge; never scroll
/// beyond the document. Returning a document-space delta keeps drag geometry
/// independent from the AppKit scroll view.
func scrollingMinimapEdgeScrollDelta(pointerX: CGFloat, viewportWidth: CGFloat,
                                    contentOffset: CGFloat, contentWidth: CGFloat,
                                    edgeWidth: CGFloat = 32, maxStep: CGFloat = 18) -> CGFloat {
    guard viewportWidth > 0, contentWidth > viewportWidth, pointerX.isFinite,
          contentOffset.isFinite, contentWidth.isFinite else { return 0 }
    let edge = min(edgeWidth, viewportWidth / 2)
    guard edge > 0 else { return 0 }
    let direction: CGFloat
    let intensity: CGFloat
    if pointerX < edge {
        direction = -1
        intensity = min(max((edge - pointerX) / edge, 0), 1)
    } else if pointerX > viewportWidth - edge {
        direction = 1
        intensity = min(max((pointerX - (viewportWidth - edge)) / edge, 0), 1)
    } else { return 0 }
    let upper = max(contentWidth - viewportWidth, 0)
    let next = min(max(contentOffset + direction * maxStep * intensity, 0), upper)
    return next - contentOffset
}

struct ScrollingMinimapLifetime {
    private var lastActivity: TimeInterval = 0
    private var hovered = false
    private var panning = false
    private var explicitlyOpen = false
    static let idleDuration: TimeInterval = 1.5

    mutating func activity(at time: TimeInterval) { lastActivity = time }
    mutating func openExplicitly(at time: TimeInterval) { explicitlyOpen = true; activity(at: time) }
    mutating func closeExplicitly() { explicitlyOpen = false }
    mutating func hover(_ active: Bool, at time: TimeInterval) { hovered = active; activity(at: time) }
    mutating func pan(_ active: Bool, at time: TimeInterval) { panning = active; activity(at: time) }
    func dismissalDelay(at time: TimeInterval) -> TimeInterval? {
        hovered || panning || explicitlyOpen ? nil : max(lastActivity + Self.idleDuration - time, 0)
    }

    var isExplicitlyOpen: Bool { explicitlyOpen }
}

@MainActor
func focusScrollingMinimapGroup(_ id: ObjectIdentifier, in workspace: Workspace) -> Bool {
    guard let group = workspace.workspaceLayoutUnits.first(where: { ObjectIdentifier($0) == id }),
          let window = group.mostRecentWindowRecursive, window.focusWindow() else { return false }
    runtime.native.focusDidMove(to: window)
    if let column = workspace.scrollingMetrics.columns.first(where: { $0.node === group }) {
        workspace.scrollingOffset = workspace.scrollingMetrics.focusedOffset(for: column, current: workspace.scrollingOffset)
        workspace.lastScrollingFocusWindowId = window.windowId
        scheduleRefreshSession(.globalObserver("scrollingMinimapSelection"))
    }
    return true
}
