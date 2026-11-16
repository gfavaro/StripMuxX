import AppKit
import SwiftUI

struct SettingsSearchDestination: Equatable {
    let id: String
    let request = UUID()
}

enum SettingsSidebarSelection: Hashable {
    case page(SettingsSidebarItem)
    case control(SettingsControl)
}

enum SettingsControl: String, CaseIterable, Hashable, Identifiable {
    case startAtLogin = "start-at-login"
    case autoReload = "auto-reload-config"
    case restoreLayouts = "native-spaces.restore-layouts"
    case restoreFrames = "native-spaces.restore-frames-on-quit"
    case autoTile = "automatically-tile-new-windows"
    case gestures = "scrolling.gesture-enabled"
    case threeFingers = "scrolling.three-finger-swipe"
    case minimap = "scrolling.minimap-enabled"
    case sensitivity = "scrolling.gesture-sensitivity"
    case width = "scrolling.column-width"
    case widthPresets = "scrolling.width-presets"
    case fullscreenWidth = "fullscreen-width"
    case loneWidth = "lone-window-width"
    case loneAlignment = "single-window-alignment"
    case centerFocused = "scrolling.center-focused-column"
    case keepHeight = "scrolling.keep-window-height"
    case gapHorizontal = "gaps.inner.horizontal"
    case gapOuterLeft = "gaps.outer.left"
    case edgePreview = "scrolling.edge-preview"
    case minimapHold = "scrolling.minimap-hold-modifiers"
    case appearance = "appearance"
    case menuBar = "menu-bar.indicator"
    case bordersEnabled = "borders.enabled"
    case borderWidth = "borders.width"
    case borderActiveColor = "borders.active-color"
    case borderInactiveColor = "borders.inactive-color"
    case borderOrder = "borders.order"
    case borderExcludeApps = "borders.exclude-apps"

    var id: String { rawValue }
    var title: String {
        switch self {
            case .startAtLogin: "Start at login"
            case .autoReload: "Reload config when it changes"
            case .restoreLayouts: "Restore strips"
            case .restoreFrames: "Put windows back on quit"
            case .autoTile: "Tile new windows automatically"
            case .gestures: "Option + two-finger pan"
            case .threeFingers: "Three-finger horizontal pan (experimental)"
            case .minimap: "Show scrolling minimap"
            case .sensitivity: "Gesture sensitivity"
            case .width: "Default column width"
            case .widthPresets: "Column size shortcuts"
            case .fullscreenWidth: "Managed fullscreen width"
            case .loneWidth: "Lone window width"
            case .loneAlignment: "Single window alignment"
            case .centerFocused: "When focusing a column"
            case .keepHeight: "Keep opening window height"
            case .gapHorizontal: "Horizontal window spacing"
            case .gapOuterLeft: "Left screen spacing"
            case .edgePreview: "Offscreen column preview"
            case .minimapHold: "Hold to keep the minimap up"
            case .appearance: "Theme"
            case .menuBar: "Menu bar indicator"
            case .bordersEnabled: "Draw window borders"
            case .borderWidth: "Border width"
            case .borderActiveColor: "Focused border color"
            case .borderInactiveColor: "Unfocused border color"
            case .borderOrder: "Border drawing order"
            case .borderExcludeApps: "Exclude apps from borders"
        }
    }
    var page: SettingsSidebarItem {
        switch self {
            case .startAtLogin, .autoReload, .restoreLayouts, .restoreFrames: .general
            case .autoTile, .gestures, .threeFingers, .minimap, .sensitivity, .width, .widthPresets, .fullscreenWidth, .loneWidth, .loneAlignment, .centerFocused, .keepHeight, .edgePreview, .minimapHold: .windows
            case .gapHorizontal, .gapOuterLeft: .appearance
            case .appearance, .menuBar, .bordersEnabled, .borderWidth, .borderActiveColor, .borderInactiveColor,
                 .borderOrder, .borderExcludeApps: .appearance
        }
    }
}

extension SettingsControl {
    /// Earlier names people still search for.
    var aliases: String {
        switch self {
            case .loneWidth: "single-window single window"
            case .loneAlignment: "position centered left right"
            case .bordersEnabled: "outline highlight frame"
            case .borderActiveColor, .borderInactiveColor: "colour accent highlight"
            default: ""
        }
    }
}

func settingsControlSearchResults(_ query: String) -> [SettingsControl] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return [] }
    return SettingsControl.allCases.filter { control in
        let searchable = "\(control.title) \(control.id) \(control.page.label) \(control.aliases)"
        return terms.allSatisfy { searchable.localizedStandardContains($0) }
    }
}

func settingsSearchSubmitSelection(controls: [SettingsControl], pages: [SettingsSidebarItem]) -> SettingsSidebarSelection? {
    if let first = controls.first { return .control(first) }
    return pages.first.map { .page($0) }
}

@MainActor
func settingsPageSearchResults(_ query: String, pages: [SettingsSidebarItem]) -> [SettingsSidebarItem] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return pages }
    let references = Dictionary(grouping: configurationReferenceSections) { $0.pane ?? .configuration }
    return pages.filter { page in
        let reference = (references[page] ?? []).map {
            "\($0.title) \($0.description) \($0.defaults ?? "") \($0.example ?? "")"
        }
        let searchable = ([page.label] + reference).joined(separator: " ")
        return terms.allSatisfy { searchable.localizedStandardContains($0) }
    }
}

struct SettingsSearchReadyKey: PreferenceKey {
    static let defaultValue: SettingsSearchDestination? = nil
    static func reduce(value: inout SettingsSearchDestination?, nextValue: () -> SettingsSearchDestination?) {
        if let next = nextValue() { value = next }
    }
}

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: SettingsSearchDestination? = nil
}
extension EnvironmentValues {
    var settingsSearchTarget: SettingsSearchDestination? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}

struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: @MainActor () -> Void

    func makeNSView(context: Context) -> SettingsSearchNSField {
        let field = SettingsSearchNSField()
        field.placeholderString = "Find settings"
        field.setAccessibilityLabel("Find settings")
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: SettingsSearchNSField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, ((field.currentEditor() as? NSTextView)?.hasMarkedText() != true) {
            field.stringValue = text
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SettingsSearchField
        init(parent: SettingsSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                  ((field.currentEditor() as? NSTextView)?.hasMarkedText() != true) else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
            parent.text = textView.string
            parent.onSubmit()
            return true
        }
    }
}

final class SettingsSearchNSField: NSSearchField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            return window?.makeFirstResponder(self) ?? false
        }
        return super.performKeyEquivalent(with: event)
    }
}
