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
            // With keep-window-height, a lone window keeps the height it opened with, at the top.
            let opened = config.scrolling.keepWindowHeight ? (node as? Window)?.lastFloatingSize?.height : nil
            let height = { (full: CGFloat) in opened.map { min(max($0, 1), full) } ?? full }
            return ColumnFrame(node: node,
                physical: Rect(topLeftX: frame.physicalFrame.minX, topLeftY: frame.physicalFrame.minY,
                               width: frame.physicalFrame.width, height: height(frame.physicalFrame.height)),
                virtual: Rect(topLeftX: frame.logicalFrame.minX, topLeftY: frame.logicalFrame.minY,
                              width: frame.logicalFrame.width, height: height(frame.logicalFrame.height)),
                visibility: frame.visibility, stackingIndex: geometry.stackingOrder.firstIndex(of: frame.index) ?? frame.index)
        } + (pinned.map { [$0] } ?? [])
    }
}
