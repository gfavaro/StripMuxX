import AppKit

struct ScrollingMinimapGeometry {
    let tiles: [CGRect]
    let viewport: CGRect
    let bounds: CGRect

    init(metrics: ScrollingWorkspaceMetrics, offset: CGFloat, bounds: CGRect) {
        self.bounds = bounds
        let start = metrics.offsetRange.lowerBound
        let span = scrollingMinimapSpan(metrics)
        // One scale for both axes: a tile has its window's shape and the viewport the display's.
        // Only a column too narrow to click is made wider than that.
        let xScale = scrollingMinimapHorizontalScale(metrics: metrics, rowHeight: bounds.height)
        let originX = bounds.midX - span * xScale / 2
        tiles = metrics.columns.map { column in
            CGRect(x: originX + (column.start - start) * xScale, y: bounds.minY,
                   width: column.width * xScale, height: bounds.height)
        }
        viewport = CGRect(x: originX + (metrics.clampedOffset(offset) - start) * xScale,
                          y: bounds.minY, width: metrics.areaWidth * xScale, height: bounds.height)
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

/// From the strip's start to the end of its last possible viewport.
func scrollingMinimapSpan(_ metrics: ScrollingWorkspaceMetrics) -> CGFloat {
    let start = metrics.offsetRange.lowerBound
    return max(max(metrics.totalWidth, metrics.offsetRange.upperBound + metrics.areaWidth) - start, 1)
}

/// Narrower than this and a tile cannot show its icon or be told apart.
let scrollingMinimapMinimumTileWidth: CGFloat = 16

/// Points of minimap per point of display, horizontally. The strip's height fills the row, so
/// this is the true scale for both axes. Only when the narrowest column would be drawn under
/// `scrollingMinimapMinimumTileWidth` is it raised, which stretches the whole map: a narrow
/// column does not need that, since a click anywhere selects the nearest tile.
func scrollingMinimapHorizontalScale(metrics: ScrollingWorkspaceMetrics, rowHeight: CGFloat) -> CGFloat {
    let truth = rowHeight / max(metrics.geometry.area.height, 1)
    let narrowest = metrics.columns.map(\.width).min() ?? .infinity
    return max(truth, scrollingMinimapMinimumTileWidth / max(narrowest, 1))
}

/// One fixed row height: room for an icon and a title, whatever the windows' shapes.
func scrollingMinimapRowHeight(metrics: ScrollingWorkspaceMetrics) -> CGFloat { 48 }

/// The panel hugs the strip at true scale: never narrower than its header and footer need,
/// never wider than `maximum` (a longer strip scrolls).
func scrollingMinimapPanelWidth(metrics: ScrollingWorkspaceMetrics, maximum: CGFloat) -> CGFloat {
    guard !metrics.columns.isEmpty else { return min(320, maximum) }
    let scale = scrollingMinimapHorizontalScale(metrics: metrics, rowHeight: scrollingMinimapRowHeight(metrics: metrics))
    return min(maximum, max(320, (scrollingMinimapSpan(metrics) * scale).rounded(.up) + 32))
}

/// The canvas is as wide as the strip at true scale, or the visible width if that is less; a
/// longer strip scrolls.
func scrollingMinimapContentWidth(metrics: ScrollingWorkspaceMetrics, visibleWidth: CGFloat) -> CGFloat {
    let scale = scrollingMinimapHorizontalScale(metrics: metrics, rowHeight: scrollingMinimapRowHeight(metrics: metrics))
    return max(visibleWidth, scrollingMinimapSpan(metrics) * scale)
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
