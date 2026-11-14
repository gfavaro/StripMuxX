public struct DebugWindowsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public var eventsStart = false
    public var eventsStop = false
    public var eventsExport = false
    public var checkModel = false
    public var gestureProbeStart = false
    public var gestureProbeStop = false
    public static let parser: CmdParser<Self> = .init(
        kind: .debugWindows,
        allowInConfig: false,
        help: debug_windows_help_generated + "\nEvent history: --events-start, --events-export, --events-stop (clears history).\nRead-only settled model scan: --check-model. Public input probe: --gesture-probe-start, --gesture-probe-stop. Use one flag at a time.\n",
        flags: [
            "--events-start": trueBoolFlag(\.eventsStart),
            "--events-stop": trueBoolFlag(\.eventsStop),
            "--events-export": trueBoolFlag(\.eventsExport),
            "--check-model": trueBoolFlag(\.checkModel),
            "--gesture-probe-start": trueBoolFlag(\.gestureProbeStart),
            "--gesture-probe-stop": trueBoolFlag(\.gestureProbeStop),
            "--window-id": ArgParser(\.windowId, upcastArgParserFun(parseUInt32SubArg)),
        ],
        posArgs: [],
    )
}
