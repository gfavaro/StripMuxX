import AppKit
import Common
import TOMLKit

/// How the strip scrolls when focus moves to a column.
enum ScrollingCenterMode: String, CaseIterable {
    /// Scroll only as far as needed to show the column.
    case never
    /// Centre the column when it would otherwise be partly off screen.
    case onOverflow = "on-overflow"
    /// Always centre the focused column.
    case always
}

struct ScrollingConfig: ConvenienceCopyable, Equatable {
    var columnWidth = 0.5
    /// How much of an offscreen column remains visible at the display edge.
    var edgePreview = 14
    var widthPresets = [0.3333, 0.5, 0.6667, 1.0]
    var gestureEnabled = true
    /// Experimental: intercept macOS's recognized three-finger horizontal Dock swipe.
    var threeFingerSwipe = false
    var gestureSensitivity = 1.0
    var minimapEnabled = true
    var centerFocusedColumn = ScrollingCenterMode.never
    /// Holding exactly these keeps the minimap up; empty turns it off.
    var minimapHoldModifiers: NSEvent.ModifierFlags = []
    /// A lone window in a column keeps the height it opened with, aligned to the top.
    var keepWindowHeight = false
    /// Experimental: milliseconds over which windows ease toward the fingers during a scroll
    /// gesture, so a fast flick moves them in many small steps. 0 follows the input directly.
    var gestureSmoothing = 0
}

func parseScrolling(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> ScrollingConfig {
    parseTable(raw, ScrollingConfig(), [
        "column-width": Parser(\.columnWidth) { raw, trace in
            parseDouble(raw, trace).filter(.semantic(trace, "Must be between 0.1 and 1.0")) { (0.1...1).contains($0) }
        },
        "width-presets": Parser(\.widthPresets) { raw, trace in
            parseArrayOfDoubles(raw, trace).filter(.semantic(trace, "Expected ascending widths between 0.1 and 1.0")) {
                !$0.isEmpty && $0.allSatisfy { $0.isFinite && (0.1...1).contains($0) } && zip($0, $0.dropFirst()).allSatisfy(<)
            }
        },
        "edge-preview": Parser(\.edgePreview) { raw, trace in
            parseInt(raw, trace).filter(.semantic(trace, "Must be between 0 and 40 points")) { (0...40).contains($0) }
        },
        "gesture-enabled": Parser(\.gestureEnabled, parseBool),
        "three-finger-swipe": Parser(\.threeFingerSwipe, parseBool),
        "gesture-sensitivity": Parser(\.gestureSensitivity) { raw, trace in
            parseDouble(raw, trace).filter(.semantic(trace, "Must be finite and greater than zero")) { $0.isFinite && $0 > 0 }
        },
        "gesture-smoothing": Parser(\.gestureSmoothing) { raw, trace in
            parseInt(raw, trace).filter(.semantic(trace, "Must be between 0 and 200 milliseconds")) { (0...200).contains($0) }
        },
        "minimap-enabled": Parser(\.minimapEnabled, parseBool),
        "keep-window-height": Parser(\.keepWindowHeight, parseBool),
        "minimap-hold-modifiers": Parser(\.minimapHoldModifiers) { raw, trace in
            parseTomlArray(raw, trace).flatMap { values in
                values.enumerated().mapAllOrFailure { index, value in
                    parseString(value, trace + .index(index)).flatMap { name -> ParsedToml<NSEvent.ModifierFlags> in
                        let flag: NSEvent.ModifierFlags? = switch name {
                            case "ctrl": .control
                            case "alt": .option
                            case "cmd": .command
                            case "shift": .shift
                            default: nil
                        }
                        return flag.orFailure(.semantic(trace + .index(index), "Expected ctrl, alt, cmd or shift"))
                    }
                }.map { NSEvent.ModifierFlags($0) }
            }
        },
        "center-focused-column": Parser(\.centerFocusedColumn) { raw, trace in
            parseString(raw, trace).flatMap {
                ScrollingCenterMode(rawValue: $0).orFailure(.semantic(trace, "Expected never, on-overflow or always"))
            }
        },
    ], trace, &errors)
}

private func parseArrayOfDoubles(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<[Double]> {
    parseTomlArray(raw, trace).flatMap { values in
        values.enumerated().mapAllOrFailure { index, value in parseDouble(value, trace + .index(index)) }
    }
}

private func parseDouble(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<Double> {
    (raw.double ?? raw.int.map(Double.init)).orFailure(expectedActualTypeError(expected: .double, actual: raw.type, trace))
}
