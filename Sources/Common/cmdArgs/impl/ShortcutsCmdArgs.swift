public struct ShortcutsCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .shortcuts,
        allowInConfig: true,
        help: "USAGE: stripmuxx shortcuts\nShow or hide the cheat sheet of the current mode's shortcuts.",
        flags: [:], posArgs: [],
    )
}
