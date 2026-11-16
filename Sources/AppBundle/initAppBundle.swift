import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    Task {
        do { try await startAppBundle() }
        catch {
            NSLog("StripMuxX startup failed: %@", String(describing: error))
            MessageModel.shared.message = Message(description: "Startup Error", body: error.localizedDescription)
        }
    }
}

@MainActor private func startAppBundle() async throws {
    initTerminationHandler()
    isCli = false
    AssistiveTechnology.startObserving()
    initServerArgs()
    var bootstrappedConfigUrl: URL? = nil
    do {
        bootstrappedConfigUrl = try ensureBootstrapConfigExistsIfNeeded()
        let editable = bootstrappedConfigUrl ?? preferredEditableConfigUrl()
        if FileManager.default.fileExists(atPath: editable.path) {
            try migrateLegacyConfiguration(at: editable)
        }
    } catch {
        MessageModel.shared.message = Message(
            description: "Config Bootstrap Error",
            body: error.localizedDescription,
        )
    }
    if try await !reloadConfig(forceConfigUrl: bootstrappedConfigUrl) {
        // The error stays on screen; the shipped defaults run until the file is fixed.
        var out = ""
        check(
            try await reloadConfig(forceConfigUrl: defaultConfigUrl, stdout: &out),
            """
            Can't load default config. Your installation is probably corrupted.
            Please don't modify '\(defaultConfigUrl)'

            \(out)
            """,
        )
    }
    // Startup never prompts for permissions: tiling reports what it is missing.
    let owner = runtime
    if !serverArgs.isReadOnly {
        NativeScrollingPan.shared.start()
        StripDockSwipeSource.shared.syncConfiguration()
    }
    GlobalObserver.initObserver()
    // Rules that move windows apply only to windows opened from now on.
    owner.native.windowsPresentAtLaunch = Set(
        (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    owner.native.startObservation { [weak owner] inventory, _ in
        // The observer reports both a read's start and its result; chrome follows results.
        guard inventory.status != .reading else { return }
        owner?.withValue { NativeObservationChrome.shared.schedule() }
    }
    isWinMuxRuntimeReady = true
    startUnixSocketServer()
    syncConfigFileWatcher()
    showSetupCheckIfNeeded()
}

@TaskLocal
var _isStartup: Bool? = false
var isStartup: Bool { _isStartup ?? dieT("isStartup is not initialized") }

struct ServerArgs: Sendable {
    var configLocation: String? = nil
    var isReadOnly: Bool = false
}

private let serverHelp = """
    USAGE: \(CommandLine.arguments.first ?? "StripMuxX.app/Contents/MacOS/StripMuxX") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print StripMuxX.app version
      --config-path <path>    Config path. Takes priority over ${XDG_CONFIG_HOME}/stripmuxx/stripmuxx.toml
                              (defaults to ~/.config/stripmuxx/stripmuxx.toml).
      --read-only             Run without mutating macOS windows.
                              Useful if you want to use only debug-windows or other query commands.
    """

nonisolated(unsafe) private var _serverArgs = ServerArgs()
var serverArgs: ServerArgs { _serverArgs }
private func initServerArgs() {
    let args = CommandLine.arguments.slice(1...) ?? []
    if args.contains(where: { $0 == "-h" || $0 == "--help" }) {
        exit(0, out: serverHelp)
    }
    var index = 0
    while index < args.count {
        let current = args[index]
        index += 1
        switch current {
            case "--version", "-v":
                exit(0, out: "\(winMuxAppVersion) \(gitHash)")
            case "--config-path":
                if let arg = args.getOrNil(atIndex: index) {
                    _serverArgs.configLocation = arg
                } else {
                    exit(1, err: "Missing <path> in --config-path flag")
                }
                index += 1
            case "--read-only": // todo rename to '--disabled' and unite with disabled feature
                _serverArgs.isReadOnly = true
            case "-NSDocumentRevisionsDebugMode" where isDebug:
                // Skip Xcode CLI args.
                // Usually it's '-NSDocumentRevisionsDebugMode NO'/'-NSDocumentRevisionsDebugMode YES'
                while args.getOrNil(atIndex: index)?.starts(with: "-") == false { index += 1 }
            default:
                exit(1, err: "Unrecognized flag '\(args.first.orDie())'")
        }
    }
    if let path = serverArgs.configLocation, !FileManager.default.fileExists(atPath: path) {
        exit(1, err: "\(path) doesn't exist")
    }
}
