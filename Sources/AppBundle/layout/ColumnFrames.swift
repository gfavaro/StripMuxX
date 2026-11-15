import AppKit
import Common

struct ColumnFrame {
    let node: TreeNode
    let physical: Rect
    let virtual: Rect
    let visibility: ScrollingColumnVisibility
    let stackingIndex: Int
}

extension Workspace {
    /// Where each column goes. Rendering and directional navigation both read these;
    /// logical columns stay distinct even when edge previews overlap.
    @MainActor
    func columnFrames(in rect: Rect, gaps: ResolvedGaps) -> [ColumnFrame] {
        guard !workspaceLayoutUnits.isEmpty else { return [] }
        let geometry = scrollingGeometry(in: rect, gaps: gaps)
        scrollingOffset = geometry.clampedOffset
        // A pinned column sits at its edge, above the strip.
        let pinned = scrollingPinSplit(in: rect, gaps: gaps).flatMap { split in
            pinnedScrollingColumn.map { ColumnFrame(node: $0, physical: split.pinned, virtual: split.pinned,
                                                    visibility: .visible, stackingIndex: geometry.columns.count) }
        }
        return zip(scrollingStripUnits, geometry.columns).map { node, frame in
            // Free-size columns remain in the horizontal strip, but keep their
            // own window height and vertical position rather than filling the tile.
            let free = (node as? Window)?.freeSizeRect
            let opened = free?.height ?? (config.scrolling.keepWindowHeight ? (node as? Window)?.lastFloatingSize?.height : nil)
            let height = { (full: CGFloat) in opened.map { min(max($0, 1), full) } ?? full }
            let y = free.map { max(frame.physicalFrame.minY, min($0.topLeftY, frame.physicalFrame.maxY - height(frame.physicalFrame.height))) } ?? frame.physicalFrame.minY
            return ColumnFrame(node: node,
                physical: Rect(topLeftX: frame.physicalFrame.minX, topLeftY: y,
                               width: frame.physicalFrame.width, height: height(frame.physicalFrame.height)),
                virtual: Rect(topLeftX: frame.logicalFrame.minX, topLeftY: y,
                              width: frame.logicalFrame.width, height: height(frame.logicalFrame.height)),
                visibility: frame.visibility, stackingIndex: geometry.stackingOrder.firstIndex(of: frame.index) ?? frame.index)
        } + (pinned.map { [$0] } ?? [])
    }
}
