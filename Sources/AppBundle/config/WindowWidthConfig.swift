import Common
import TOMLKit

/// The shape of a lone tiled window and where it sits.
struct WindowWidthSettings: ConvenienceCopyable, Equatable {
    var aspectRatio: Double?
    var singleWindowAlignment: SingleWindowAlignment?

    func overlaying(_ base: Self) -> Self {
        Self(aspectRatio: aspectRatio ?? base.aspectRatio,
             singleWindowAlignment: singleWindowAlignment ?? base.singleWindowAlignment)
    }
}

/// Width as a multiple of height for a lone window; 0, the default, lets it fill the width.
let defaultSingleWindowAspectRatio = 0.0

/// `[display.<pattern>]`: width settings for one display.
struct DisplayWindowSettings {
    let selector: MonitorDescription
    let settings: WindowWidthSettings
}

func parseAspectRatio(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<Double> {
    guard let value: Double = parseSimpleType(raw), value.isFinite, (0...6).contains(value) else {
        return .failure(.semantic(trace, "Expected a finite aspect ratio from 0 (fill the width) to 6"))
    }
    return .success(value)
}

func parseOptionalSingleWindowAlignment(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<SingleWindowAlignment?> {
    parseString(raw, trace).flatMap {
        SingleWindowAlignment(rawValue: $0).map { Optional($0) }
            .orFailure(.semantic(trace, "Expected center, left or right"))
    }
}

private let displayWindowParsers: [String: any ParserProtocol<WindowWidthSettings>] = [
    "single-window-aspect-ratio": Parser(\.aspectRatio) { raw, trace in parseAspectRatio(raw, trace).map { Optional($0) } },
    "single-window-alignment": Parser(\.singleWindowAlignment, parseOptionalSingleWindowAlignment),
]

func parseDisplayWindowSettings(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                                _ errors: inout [TomlParseError]) -> [DisplayWindowSettings] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, trace))
        return []
    }
    return table.compactMap { pattern, value in
        let path = trace + .key(pattern)
        guard let selector = parseMonitorDescription(pattern).toParsedToml(path).getOrNil(appendErrorTo: &errors) else { return nil }
        return DisplayWindowSettings(selector: selector,
            settings: parseTable(value, WindowWidthSettings(), displayWindowParsers, path, &errors))
    }
}

/// Named displays beat main/secondary; exact identities beat names.
@MainActor
func matchingWindowSettings(_ rules: [DisplayWindowSettings], on monitor: Monitor) -> WindowWidthSettings? {
    func priority(_ selector: MonitorDescription) -> Int {
        switch selector {
            case .uuid, .hardware, .sequenceNumber: Int.max
            case .pattern(let name, _): name.count
            case .main, .secondary: 0
        }
    }
    return rules.sorted {
        let a = priority($0.selector), b = priority($1.selector)
        return a == b ? $0.selector.selector < $1.selector.selector : a > b
    }.first { rule in
        switch rule.selector {
            case .pattern(_, let regex): monitor.name.contains(regex.val)
            default: rule.selector.resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
        }
    }?.settings
}

extension Workspace {
    @MainActor
    var windowWidthSettings: WindowWidthSettings {
        let global = WindowWidthSettings(aspectRatio: config.singleWindowAspectRatio,
                                         singleWindowAlignment: config.singleWindowAlignment)
        return matchingWindowSettings(config.displayWindowSettings, on: workspaceMonitor)?.overlaying(global) ?? global
    }
}
