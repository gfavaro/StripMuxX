public struct ScrollingWidthCmdArgs: CmdArgs {
    public enum Action: String, CaseIterable, Sendable { case next, previous, full }
    /// A preset step, or a share of the display between 0.1 and 1.
    public enum Target: Equatable, Sendable {
        case action(Action)
        case share(Double)
    }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingWidth,
        allowInConfig: true,
        help: "USAGE: stripmuxx scrolling-width (next|previous|full|<share>)",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.target, parseTarget, placeholder: "(next|previous|full|<share>)")],
    )
    public var target: Lateinit<Target> = .uninitialized
}

private func parseTarget(input: PosArgParserInput) -> ParsedCliArgs<ScrollingWidthCmdArgs.Target> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected next, previous, full or a share", advanceBy: 0) }
    if let action = ScrollingWidthCmdArgs.Action(rawValue: raw) { return .succ(.action(action), advanceBy: 1) }
    if let share = Double(raw), share.isFinite, (0.1...1).contains(share) { return .succ(.share(share), advanceBy: 1) }
    return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingWidthCmdArgs.Action.unionLiteral) or a share from 0.1 to 1", advanceBy: 1)
}
