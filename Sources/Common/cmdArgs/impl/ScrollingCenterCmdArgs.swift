public struct ScrollingCenterCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingCenter,
        allowInConfig: true,
        help: "USAGE: stripmuxx scrolling-center\nCenter the focused column in a scrolling workspace.",
        flags: [:], posArgs: [],
    )
}
