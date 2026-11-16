import AppKit
import Common
import HotKey
import TOMLKit
import OrderedCollections

@MainActor
func readConfig(forceConfigUrl: URL? = nil) -> Result<(Config, URL), String> {
    let configUrl: URL
    if let forceConfigUrl {
        configUrl = forceConfigUrl
    } else {
        switch findCustomConfigUrl() {
            case .file(let url): configUrl = url
            case .noCustomConfigExists: configUrl = defaultConfigUrl
            case .ambiguousConfigError(let candidates):
                let msg = """
                    Ambiguous config error. Several configs found:
                    \(candidates.map(\.path).joined(separator: "\n"))
                    """
                return .failure(msg)
        }
    }
    let text: String
    do { text = try String(contentsOf: configUrl, encoding: .utf8) }
    catch { return .failure("Failed to read \(configUrl.path): \(error.localizedDescription)") }
    let (parsedConfig, errors) = parseConfig(text)

    if errors.isEmpty {
        return .success((parsedConfig, configUrl))
    } else {
        let msg = """
            Failed to parse \(configUrl.absoluteURL.path)

            \(errors.map(\.description).joined(separator: "\n\n"))
            """
        return .failure(msg)
    }
}

private let keyMappingConfigRootKey = "key-mapping"
private let modeConfigRootKey = "mode"
private let persistentWorkspacesKey = "persistent-workspaces"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
private let configParser: [String: any ParserProtocol<Config>] = [
    "native-spaces": Parser(\.nativeSpaces, parseNativeSpaces),
    "borders": Parser(\.windowBorders, parseWindowBorders),
    "accent-color": Parser(\.accentColor) { raw, trace in
        parseString(raw, trace).flatMap { color in
            guard color.hasPrefix("#"), color.count == 7,
                  UInt32(color.dropFirst(), radix: 16) != nil else {
                return .failure(.semantic(trace, "Expected #RRGGBB"))
            }
            return .success(color.uppercased())
        }
    },
    "appearance": Parser(\.appearance) { raw, backtrace in
        parseString(raw, backtrace).flatMap {
            AppAppearance(rawValue: $0).orFailure(.semantic(backtrace, "Possible values: system, light, dark"))
        }
    },
    "config-version": Parser(\.configVersion, parseConfigVersion),

    "after-startup-command": Parser(\.afterStartupCommand) { parseCommandOrCommands($0).toParsedToml($1) },

    "on-focus-changed": Parser(\.onFocusChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-mode-changed": Parser(\.onModeChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-focused-monitor-changed": Parser(\.onFocusedMonitorChanged) { parseCommandOrCommands($0).toParsedToml($1) },



    "start-at-login": Parser(\.startAtLogin, parseBool),
    "auto-reload-config": Parser(\.autoReloadConfig, parseBool),
    "automatically-tile-new-windows": Parser(\.automaticallyTileNewWindows, parseBool),
    "scrolling": Parser(\.scrolling, parseScrolling),
    persistentWorkspacesKey: Parser(\.persistentWorkspaces, parsePersistentWorkspaces),
    "exec-on-workspace-change": Parser(\.execOnWorkspaceChange, parseArrayOfStrings),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    "single-window-alignment": Parser(\.singleWindowAlignment) { raw, backtrace in
        parseString(raw, backtrace).flatMap {
            SingleWindowAlignment(rawValue: $0).orFailure(.semantic(backtrace, "Expected center, left or right"))
        }
    },
    "fullscreen-width": Parser(\.fullscreenWidth, parseFullscreenWidth),
    "lone-window-width": Parser(\.loneWindowWidth, parseFullscreenWidth),
    "display": Parser(\.displayWindowSettings, parseDisplayWindowSettings),
    "single-window-aspect-ratio": Parser(\.singleWindowAspectRatio, parseSingleWindowAspectRatio),
    "gaps": Parser(\.gaps, parseGaps),
    "menu-bar": Parser(\.menuBar, parseMenuBar),
    "modifiers": Parser(\.modifierSides, parseModifierSides),
    "workspace-to-monitor-force-assignment": Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "on-window-detected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),

]

extension ParsedCmd where T == any Command {
    fileprivate func toEither() -> Parsed<T> {
        return switch self {
            case .cmd(let a):
                a.info.allowInConfig
                    ? .success(a)
                    : .failure("Command '\(a.info.kind.rawValue)' cannot be used in config")
            case .help(let a): .failure(a)
            case .failure(let a): .failure(a)
        }
    }
}

extension Command {
    fileprivate var isMacOsNativeCommand: Bool { // Problem ID-B6E178F2
        self is MacosNativeMinimizeCommand || self is MacosNativeFullscreenCommand
    }
}

/// Commands of removed features are left out; see `removedConfiguration(in:)`.
func parseCommandOrCommands(_ raw: TOMLValueConvertible) -> Parsed<[any Command]> {
    if let rawString = raw.string {
        if isRemovedCommandScript(rawString) { return .success([]) }
        return parseCommand(rawString).toEither().map { [$0] }
    } else if let rawArray = raw.array {
        let kept = (0 ..< rawArray.count).filter { rawArray[$0].string.map(isRemovedCommandScript) != true }
        let commands: Parsed<[any Command]> = kept.mapAllOrFailure { index in
            let rawString: String = rawArray[index].string ?? expectedActualTypeError(expected: .string, actual: rawArray[index].type)
            return parseCommand(rawString).toEither()
        }
        return commands.filter("macos-native-* commands are only allowed to be the last commands in the list") {
            !$0.dropLast().contains(where: { $0.isMacOsNativeCommand })
        }
    } else {
        return .failure(expectedActualTypeError(expected: [.string, .array], actual: raw.type))
    }
}

@MainActor func parseConfig(_ rawToml: String) -> (config: Config, errors: [TomlParseError]) { // todo change return value to Result
    let rawTable: TOMLTable
    do {
        rawTable = try TOMLTable(string: migratingLegacyMinimumWorkspaceCount(in: rawToml))
    } catch let e as TOMLParseError {
        return (defaultConfig, [.syntax(e.debugDescription)])
    } catch let e {
        return (defaultConfig, [.syntax(e.localizedDescription)])
    }

    var errors: [TomlParseError] = []

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &errors)
    // Keys of removed features are not errors; they are listed instead.
    config.ignoredConfiguration = removedConfiguration(in: rawTable)
    let ignoredPaths = removedRootConfigKeys.union(removedTableConfigKeys.flatMap { table, keys in keys.map { "\(table).\($0)" } })
    errors.removeAll { error in
        guard case .semantic(let backtrace, _) = error else { return false }
        return ignoredPaths.contains(backtrace.description)
    }
    // Omitted width uses Dinky's full-width default. Only an explicit legacy key
    // retains the old aspect-ratio behavior until a width is configured.
    if config.fullscreenWidth == nil && !rawTable.contains(key: "single-window-aspect-ratio") {
        config.fullscreenWidth = 1.0
    }

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &errors) }) {
        config.keyMapping = mapping
    }

    // Parse modeConfigRootKey after keyMappingConfigRootKey
    if let modes = rawTable[modeConfigRootKey].flatMap({ parseModes($0, .rootKey(modeConfigRootKey), &errors, config.keyMapping.resolve()) }) {
        config.modes = modes
    }
    if rawTable.contains(key: modeConfigRootKey) && !config.modes.keys.contains(mainModeId) {
        errors += [.semantic(.rootKey(modeConfigRootKey), "Please specify '\(mainModeId)' mode")]
    }

    if config.configVersion <= 1 {
        if rawTable.contains(key: persistentWorkspacesKey) {
            errors += [.semantic(.rootKey(persistentWorkspacesKey), "This config option is only available since 'config-version = 2'")]
        }
        // Desktops are macOS's; only an explicit persistent-workspaces list ever adds one.
        // (AeroSpace derived persistent names from version-1 shortcuts, which here
        // would create a desktop for every `workspace N` binding.)
    }

    return (config, errors)
}

func parseConfigVersion(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    let min = 1
    let max = 2
    return parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be in [\(min), \(max)] range")) { (min ... max).contains($0) }
}

func parseInt(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    raw.int.orFailure(expectedActualTypeError(expected: .int, actual: raw.type, backtrace))
}

func parseString(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<String> {
    raw.string.orFailure(expectedActualTypeError(expected: .string, actual: raw.type, backtrace))
}

func parseSimpleType<T>(_ raw: TOMLValueConvertible) -> T? {
    if T.self == Double.self { return (raw.double ?? raw.int.map(Double.init)) as? T }
    return (raw.int as? T) ?? (raw.string as? T) ?? (raw.bool as? T)
}

func parseTomlArray(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<TOMLArray> {
    raw.array.orFailure(expectedActualTypeError(expected: .array, actual: raw.type, backtrace))
}

func parseTable<T: ConvenienceCopyable>(
    _ raw: TOMLValueConvertible,
    _ initial: T,
    _ fieldsParser: [String: any ParserProtocol<T>],
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> T {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return initial
    }
    return table.parseTable(initial, fieldsParser, backtrace, &errors)
}

private func skipParsing<T: Sendable>(_ value: T) -> @Sendable (_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<T> {
    { _, _ in .success(value) }
}

private func parsePersistentWorkspaces(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<OrderedSet<String>> {
    parseArrayOfStrings(raw, backtrace)
        .flatMap { arr in
            let set = arr.toOrderedSet()
            return set.count == arr.count ? .success(set) : .failure(.semantic(backtrace, "Contains duplicated workspace names"))
        }
}

func parseArrayOfStrings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[String]> {
    parseTomlArray(raw, backtrace)
        .flatMap { arr in
            arr.enumerated().mapAllOrFailure { (index, elem) in
                parseString(elem, backtrace + .index(index))
            }
        }
}

extension Parsed where Failure == String {
    func toParsedToml(_ backtrace: TomlBacktrace) -> ParsedToml<Success> {
        mapError { .semantic(backtrace, $0) }
    }
}

func parseBool(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Bool> {
    raw.bool.orFailure(expectedActualTypeError(expected: .bool, actual: raw.type, backtrace))
}
