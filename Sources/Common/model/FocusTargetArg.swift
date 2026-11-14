public enum FocusTargetArg: Equatable, Sendable {
    case direction(CardinalDirection)
    case dfsRelative(DfsNextPrev)
}

extension FocusTargetArg: CaseIterable {
    public static var allCases: [FocusTargetArg] {
        CardinalDirection.allCases.map { .direction($0) } +
            DfsNextPrev.allCases.map { .dfsRelative($0) }
    }
}

extension FocusTargetArg: RawRepresentable {
    public typealias RawValue = String

    public init?(rawValue: RawValue) {
        if let direction = CardinalDirection(rawValue: rawValue) {
            self = .direction(direction)
        } else if let nextPrev = DfsNextPrev(rawValue: rawValue) {
            self = .dfsRelative(nextPrev)
        } else {
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
            case .direction(let direction): direction.rawValue
            case .dfsRelative(let nextPrev): nextPrev.rawValue
        }
    }
}
