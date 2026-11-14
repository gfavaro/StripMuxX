public struct ScrollingPanCmdArgs: CmdArgs {
    public enum Direction: String, CaseIterable, Sendable { case left, right, focus }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingPan,
        allowInConfig: true,
        help: "USAGE: stripmuxx scrolling-pan (left|right|focus)\nMove the viewport without changing focus.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.direction, parsePanDirection, placeholder: Direction.unionLiteral)],
    )
    public var direction: Lateinit<Direction> = .uninitialized
}
private func parsePanDirection(input: PosArgParserInput) -> ParsedCliArgs<ScrollingPanCmdArgs.Direction> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected left, right or focus", advanceBy: 0) }
    guard let value = ScrollingPanCmdArgs.Direction(rawValue: raw) else { return .fail("Invalid pan direction", advanceBy: 1) }
    return .succ(value, advanceBy: 1)
}

public struct ScrollingWidthPixelsCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingWidthPixels, allowInConfig: true,
        help: "USAGE: stripmuxx scrolling-width-pixels <points>\nSet absolute column width.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.points, parsePixelWidth, placeholder: "<points>")],
    )
    public var points: Lateinit<UInt> = .uninitialized
}
private func parsePixelWidth(input: PosArgParserInput) -> ParsedCliArgs<UInt> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected positive points", advanceBy: 0) }
    guard let number = UInt(raw), (1...100_000).contains(number) else {
        return .fail("Width must be between 1 and 100000 points", advanceBy: 1)
    }
    return .succ(number, advanceBy: 1)
}
