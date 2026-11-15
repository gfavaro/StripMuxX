import AppKit

struct ScrollingMinimapGeometry {
    let tiles: [CGRect]
    let viewport: CGRect
    let bounds: CGRect

    init(metrics: ScrollingWorkspaceMetrics, offset: CGFloat, bounds: CGRect) {
        self.bounds = bounds
        let start = metrics.offsetRange.lowerBound
        let span = scrollingMinimapSpan(metrics)
        // Tiles fill the row's height; only widths are to scale, so columns compare by
        // width and the viewport sits over the columns on screen. A short strip is capped
        // so the visible part never takes more than most of the panel, and centred.
        let xScale = min(max(bounds.width, 0) / span,
                         scrollingMinimapMaximumViewportShare * max(bounds.width, 0) / max(metrics.areaWidth, 1),
                         // The compact cap gives way to keep every column clickable (32 pt).
                         max(scrollingMinimapMaximumTypicalTileWidth / max(scrollingMinimapTypicalColumnWidth(metrics), 1),
                             32 / max(metrics.columns.map(\.width).min() ?? 1, 1)))
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

/// The share of the panel the on-screen part of the strip may take at most.
let scrollingMinimapMaximumViewportShare: CGFloat = 0.6

/// From the strip's start to the end of its last possible viewport.
func scrollingMinimapSpan(_ metrics: ScrollingWorkspaceMetrics) -> CGFloat {
    let start = metrics.offsetRange.lowerBound
    return max(max(metrics.totalWidth, metrics.offsetRange.upperBound + metrics.areaWidth) - start, 1)
}

/// A typical column is drawn no wider than this; a few columns stay compact and centred.
let scrollingMinimapMaximumTypicalTileWidth: CGFloat = 55

func scrollingMinimapTypicalColumnWidth(_ metrics: ScrollingWorkspaceMetrics) -> CGFloat {
    let widths = metrics.columns.map(\.width).sorted()
    return widths.isEmpty ? metrics.areaWidth : widths[widths.count / 2]
}

/// One fixed row height: room for an icon and a title, whatever the windows' shapes.
func scrollingMinimapRowHeight(metrics: ScrollingWorkspaceMetrics) -> CGFloat { 48 }

/// The panel hugs the strip at its compact size: never narrower than its header and
/// footer need, never wider than `maximum`.
func scrollingMinimapPanelWidth(metrics: ScrollingWorkspaceMetrics, maximum: CGFloat) -> CGFloat {
    let widths = metrics.columns.map(\.width)
    guard let narrowest = widths.min() else { return min(320, maximum) }
    let scale = max(scrollingMinimapMaximumTypicalTileWidth / max(scrollingMinimapTypicalColumnWidth(metrics), 1),
                    32 / max(narrowest, 1))
    return min(maximum, max(320, (scrollingMinimapSpan(metrics) * scale).rounded(.up) + 32))
}

/// The strip fills the visible width. When that would make typical columns narrower than
/// their compact width or any column too narrow to click (32 pt), the canvas grows and scrolls.
func scrollingMinimapContentWidth(metrics: ScrollingWorkspaceMetrics, visibleWidth: CGFloat) -> CGFloat {
    let span = scrollingMinimapSpan(metrics)
    let widths = metrics.columns.map(\.width).sorted()
    guard let narrowest = widths.first else { return visibleWidth }
    let typical = widths[widths.count / 2]
    let scale = max(visibleWidth / span, 32 / max(narrowest, 1),
                    scrollingMinimapMaximumTypicalTileWidth / max(typical, 1))
    return max(visibleWidth, span * scale)
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
