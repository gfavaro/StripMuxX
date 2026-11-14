import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "resources/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
// Domain accessors; storage and lifetime belong to the runtime.
@MainActor var config: Config {
    get { runtime.configuration.value }
    set { runtime.configuration.value = newValue }
}
@MainActor var configUrl: URL {
    get { runtime.configuration.url }
    set { runtime.configuration.url = newValue }
}

struct Config: ConvenienceCopyable {
    var nativeSpaces = NativeSpacesConfig()
    var appearance: AppAppearance = .system
    var configVersion: Int = 1
    var afterStartupCommand: [any Command] = []
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var automaticallyTileNewWindows: Bool = true
    var scrolling = ScrollingConfig()
    /// The highest number among these is how many desktops are kept: missing ones are added.
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var modifierSides = ModifierSides()
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var fullscreenWidth: Double?
    /// Independent width for a lone tiled window; nil falls back to fullscreen-width.
    var loneWindowWidth: Double?
    var displayWindowSettings: [DisplayWindowSettings] = []
    var singleWindowAlignment: SingleWindowAlignment = .center
    var singleWindowAspectRatio: DynamicConfigValue<Double> = .constant(1.5)
    var gaps: Gaps = .zero
    var menuBar = MenuBarConfig()
    /// Where a desktop added for `persistent-workspaces` is created.
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: [any Command] = []
    /// What the file sets for removed features; skipped, and listed by `doctor`.
    var ignoredConfiguration: [String] = []
}

import TOMLKit

struct NativeSpacesConfig: ConvenienceCopyable, Equatable {
    var restoreLayouts = true
    var restoreFramesOnQuit = true
}

func parseNativeSpaces(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> NativeSpacesConfig {
    parseTable(raw, NativeSpacesConfig(), nativeSpacesParsers, trace, &errors)
}

private let nativeSpacesParsers: [String: any ParserProtocol<NativeSpacesConfig>] = [
    "restore-layouts": Parser(\.restoreLayouts, parseBool),
    "restore-frames-on-quit": Parser(\.restoreFramesOnQuit, parseBool),
]

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var nativeAppearance: NSAppearance? {
        switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum SingleWindowAlignment: String, CaseIterable, Sendable { case center, left, right }
