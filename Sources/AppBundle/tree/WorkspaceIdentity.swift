import AppKit

struct WorkspaceId: RawRepresentable, Hashable, Identifiable, Sendable, Codable, CustomStringConvertible, Comparable {
    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func < (lhs: WorkspaceId, rhs: WorkspaceId) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }
}

struct MonitorViewportId: Hashable, Sendable, Codable, CustomStringConvertible {
    let topLeftCorner: CGPoint

    var description: String {
        "\(topLeftCorner.x),\(topLeftCorner.y)"
    }

    init(topLeftCorner: CGPoint) {
        self.topLeftCorner = topLeftCorner
    }

    @MainActor
    init(_ monitor: Monitor) {
        self.topLeftCorner = monitor.rect.topLeftCorner
    }
}
