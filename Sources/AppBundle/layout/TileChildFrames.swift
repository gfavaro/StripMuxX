import AppKit
import Common

extension TilingContainer {
    @MainActor
    func tileChildFrames(in rect: Rect, gaps: ResolvedGaps) -> [(physical: Rect, virtual: Rect, weight: CGFloat)] {
        let children = frameLayoutChildren
        guard !children.isEmpty else { return [] }
        let axis = orientation
        let calculated = TileLayoutGeometry.calculate(TileLayoutInput(
            origin: rect.topLeftCorner, size: rect.size, horizontal: axis == .h,
            innerGap: CGFloat(gaps.inner.get(axis).toDouble()), weights: children.map { $0.getWeight(axis) },
            minimumExtents: children.map { $0.minimumLayoutExtent(along: axis, gaps: gaps) }))
        return calculated.map { frame in
            (Rect(topLeftX: frame.physical.minX, topLeftY: frame.physical.minY,
                  width: frame.physical.width, height: frame.physical.height),
             Rect(topLeftX: frame.virtual.minX, topLeftY: frame.virtual.minY,
                  width: frame.virtual.width, height: frame.virtual.height), frame.weight)
        }
    }
}
