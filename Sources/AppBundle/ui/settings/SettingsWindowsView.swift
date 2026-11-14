import AppKit
import SwiftUI
import Common

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject private var minimums = PersistedAppMinimums.shared
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("scrolling.column-width", load: { Int((config.scrolling.columnWidth * 100).rounded()) }) private var scrollingColumnWidth: Int
    @SettingsDraft("scrolling.width-presets", load: { config.scrolling.widthPresets.map { String($0 * 100) }.joined(separator: ", ") }) private var scrollingWidthPresets: String
    @SettingsDraft("scrolling.gesture-enabled", load: { config.scrolling.gestureEnabled }) private var scrollingGestureEnabled: Bool
    @SettingsDraft("scrolling.gesture-sensitivity", load: { String(config.scrolling.gestureSensitivity) }) private var scrollingSensitivity: String
    @SettingsDraft("scrolling.minimap-enabled", load: { config.scrolling.minimapEnabled }) private var scrollingMinimapEnabled: Bool
    @SettingsDraft("scrolling.keep-window-height", load: { config.scrolling.keepWindowHeight }) private var scrollingKeepWindowHeight: Bool
    @SettingsDraft("scrolling.center-focused-column", load: { config.scrolling.centerFocusedColumn }) private var scrollingCenterMode: ScrollingCenterMode
    @SettingsDraft("scrolling.minimap-hold-modifiers", load: { minimapHoldModifierNames(config.scrolling.minimapHoldModifiers) }) private var minimapHoldModifiers: String
    @SettingsDraft("automatically-tile-new-windows", load: { config.automaticallyTileNewWindows }) private var automaticallyTileNewWindows: Bool
    @State private var confirmsForgetAllMinimums = false

    @SettingsDraft("single-window-alignment", load: { config.singleWindowAlignment }) private var singleWindowAlignment: SingleWindowAlignment
    @SettingsDraft("fullscreen-width", load: { config.fullscreenWidth ?? 1.0 }) private var fullscreenWidth: Double

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", id: "automatically-tile-new-windows", isOn: $automaticallyTileNewWindows, help: "A new window becomes a column right of the focused one. Off leaves new windows floating.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
            }
            learnedMinimumsSection
            SettingsSection("Lone windows and fullscreen") {
                SettingsStepper("Width", id: "fullscreen-width", value: Binding(
                    get: { Int((fullscreenWidth * 100).rounded()) },
                    set: { fullscreenWidth = Double($0) / 100 }), range: 10...100,
                    help: "Share of the available width for a lone tiled window or StripMuxX fullscreen. Display overrides take priority.", unit: "%") {
                    persistConfig(section: nil, key: "fullscreen-width", value: String(fullscreenWidth))
                }
                Text("Applies after outer gaps on any display. Fullscreen stays centered; alignment below applies to lone tiled windows.")
                    .font(.callout).foregroundStyle(.secondary)
                if let width = focus.workspace.windowWidthSettings.fullscreenWidth {
                    Text("Current desktop: \(Int((width * 100).rounded()))% · \(focus.workspace.windowWidthSettings.singleWindowAlignment?.rawValue ?? "center") · \(focus.workspace.workspaceMonitor.name)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("The current desktop uses the legacy aspect-ratio setting. Saving a width switches to percentage sizing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                SettingsPicker("Alignment", id: "single-window-alignment", selection: $singleWindowAlignment,
                    help: "Position a lone tiled window within the available area after gaps.") {
                    Text("Centered").tag(SingleWindowAlignment.center)
                    Text("Left").tag(SingleWindowAlignment.left)
                    Text("Right").tag(SingleWindowAlignment.right)
                } onChange: { persistRootString("single-window-alignment", singleWindowAlignment.rawValue) }

            }
            SettingsSection("Gestures") {
                Text("macOS swipes between desktops and opens Mission Control. Hold Option and scroll with two fingers to pan the strip.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            scrollingSettingsSection
        }
        .navigationTitle("Windows")
        .confirmationDialog("Forget all learned minimum sizes?", isPresented: $confirmsForgetAllMinimums, titleVisibility: .visible) {
            Button("Forget All", role: .destructive) { minimums.forgetAll() }
        } message: {
            Text("StripMuxX will relearn app minimums from future resize attempts.")
        }

    }

    private var learnedMinimumsSection: some View {
        SettingsSection("Learned minimum sizes") {
            if minimums.snapshot.isEmpty {
                Text("No confirmed app minimum sizes have been saved.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(minimums.snapshot) { evidence in
                    HStack(spacing: 12) {
                        Image(nsImage: minimumAppIcon(evidence.bundleId))
                            .resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(minimumAppName(evidence.bundleId)).font(.body)
                            Text(evidence.bundleId).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(minimumSizeDescription(evidence.size)).font(.callout.monospacedDigit())
                            if !evidence.unknownAxes.isEmpty {
                                Text("Unknown \(evidence.unknownAxes.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Forget") { minimums.forget(evidence.bundleId) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                Button("Forget All…", role: .destructive) { confirmsForgetAllMinimums = true }
                    .padding(.top, 4)
            }
            Text("Only stable, confirmed resize refusals are saved. Forgetting an app also clears its current evidence and prevents an older saved snapshot from restoring it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var scrollingSettingsSection: some View {
        SettingsSection("Strip") {
            SettingsStepper("Default column width", id: "scrolling.column-width", value: $scrollingColumnWidth,
                range: 10...100, help: "Preferred share of the usable display width. A lone column still fills the display.", unit: "%") {
                persistConfig(section: "scrolling", key: "column-width", value: String(Double(scrollingColumnWidth) / 100))
            }
            SettingsTextField("Width presets (%)", id: "scrolling.width-presets", text: $scrollingWidthPresets,
                help: "Comma-separated ascending percentages from 10 to 100.", validate: scrollingPresetError) {
                if let values = scrollingPresetValues(scrollingWidthPresets) {
                    persistConfig(section: "scrolling", key: "width-presets", value: "[" + values.map { String($0) }.joined(separator: ", ") + "]")
                }
            }
            SettingsToggle("Option + two-finger pan", id: "scrolling.gesture-enabled", isOn: $scrollingGestureEnabled,
                help: "Pan the strip with a horizontal two-finger scroll while holding Option.") {
                persistConfig(section: "scrolling", key: "gesture-enabled", value: scrollingGestureEnabled ? "true" : "false")
            }
            SettingsTextField("Gesture sensitivity", id: "scrolling.gesture-sensitivity", text: $scrollingSensitivity,
                help: "Multiplier for the default pan distance. Enter a finite value greater than zero.", validate: scrollingSensitivityError) {
                if let value = Double(scrollingSensitivity), value.isFinite, value > 0 {
                    persistConfig(section: "scrolling", key: "gesture-sensitivity", value: String(value))
                }
            }
            SettingsToggle("Keep each window's opening height", id: "scrolling.keep-window-height", isOn: $scrollingKeepWindowHeight,
                help: "A window alone in its column keeps the height it opened with, aligned to the top, instead of filling the column.") {
                persistConfig(section: "scrolling", key: "keep-window-height", value: scrollingKeepWindowHeight ? "true" : "false")
            }
            SettingsToggle("Show scrolling minimap", id: "scrolling.minimap-enabled", isOn: $scrollingMinimapEnabled,
                help: "Show the strip's map while panning and allow it to be opened from the menu or a shortcut.") {
                persistConfig(section: "scrolling", key: "minimap-enabled", value: scrollingMinimapEnabled ? "true" : "false")
            }
            SettingsTextField("Hold to keep the minimap up", id: "scrolling.minimap-hold-modifiers", text: $minimapHoldModifiers,
                help: "Comma-separated keys from ctrl, alt, cmd and shift; while they are held the minimap stays open. Empty turns this off.",
                validate: minimapHoldModifierError) {
                if minimapHoldModifierError(minimapHoldModifiers) == nil {
                    persistConfig(section: "scrolling", key: "minimap-hold-modifiers", value: tomlCommaSeparatedStringArray(minimapHoldModifiers))
                }
            }
            SettingsPicker("Centre the focused column", id: "scrolling.center-focused-column", selection: $scrollingCenterMode,
                help: "Where focusing a column scrolls the strip.") {
                Text("Never: just bring it into view").tag(ScrollingCenterMode.never)
                Text("Only when the strip overflows").tag(ScrollingCenterMode.onOverflow)
                Text("Always").tag(ScrollingCenterMode.always)
            } onChange: { persistConfig(section: "scrolling", key: "center-focused-column", value: "'\(scrollingCenterMode.rawValue)'") }
        }
    }

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistConfig(section: nil, key: key, value: value ? "true" : "false")
    }

    private func persistRootString(_ key: String, _ value: String) { persistConfig(section: nil, key: key, value: "'\(value)'") }
    private func persistConfig(section: String?, key: String, value: String) {
        persistSettingsConfig(section: section, key: key, renderedValue: value, model: model)
    }
}

private let minimapHoldModifierFlags: [(String, NSEvent.ModifierFlags)] = [("ctrl", .control), ("alt", .option), ("cmd", .command), ("shift", .shift)]

func minimapHoldModifierNames(_ flags: NSEvent.ModifierFlags) -> String {
    minimapHoldModifierFlags.filter { flags.contains($0.1) }.map(\.0).joined(separator: ", ")
}

func minimapHoldModifierError(_ text: String) -> String? {
    let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let unknown = names.filter { name in !minimapHoldModifierFlags.contains { $0.0 == name } }
    return unknown.isEmpty ? nil : "Unknown key: \(unknown.joined(separator: ", ")). Use ctrl, alt, cmd or shift."
}

private func minimumAppName(_ bundleId: String) -> String {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
        ?? bundleId
}

private func minimumAppIcon(_ bundleId: String) -> NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Application") ?? NSImage(size: NSSize(width: 24, height: 24))
}

private func minimumSizeDescription(_ size: CGSize) -> String {
    let width = size.width == 0 ? "?" : String(Int(size.width.rounded()))
    let height = size.height == 0 ? "?" : String(Int(size.height.rounded()))
    return "\(width) × \(height)"
}

private func scrollingPresetValues(_ text: String) -> [Double]? {
    let parts = text.split(separator: ",", omittingEmptySubsequences: false)
    let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.map { $0 / 100 }
    guard values.count == parts.count, !values.isEmpty,
          values.allSatisfy({ $0.isFinite && (0.1...1).contains($0) }),
          zip(values, values.dropFirst()).allSatisfy(<) else { return nil }
    return values
}

private func scrollingPresetError(_ text: String) -> String? {
    scrollingPresetValues(text) == nil ? "Enter ascending percentages between 10 and 100, separated by commas." : nil
}

private func scrollingSensitivityError(_ text: String) -> String? {
    guard let value = Double(text), value.isFinite, value > 0 else { return "Enter a finite value greater than zero." }
    return nil
}
