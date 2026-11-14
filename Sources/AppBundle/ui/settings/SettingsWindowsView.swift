import AppKit
import SwiftUI
import Common

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject private var minimums = PersistedAppMinimums.shared
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("scrolling.column-width", load: { Int((config.scrolling.columnWidth * 100).rounded()) }) private var scrollingColumnWidth: Int
    @SettingsDraft("scrolling.edge-preview", load: { config.scrolling.edgePreview }) private var edgePreview: Int
    @SettingsDraft("scrolling.width-presets", load: { config.scrolling.widthPresets.map { String($0 * 100) }.joined(separator: ", ") }) private var scrollingWidthPresets: String
    @SettingsDraft("scrolling.gesture-enabled", load: { config.scrolling.gestureEnabled }) private var scrollingGestureEnabled: Bool
    @SettingsDraft("scrolling.three-finger-swipe", load: { config.scrolling.threeFingerSwipe }) private var threeFingerSwipe: Bool
    @SettingsDraft("scrolling.gesture-sensitivity", load: { String(config.scrolling.gestureSensitivity) }) private var scrollingSensitivity: String
    @SettingsDraft("scrolling.minimap-enabled", load: { config.scrolling.minimapEnabled }) private var scrollingMinimapEnabled: Bool
    @SettingsDraft("scrolling.keep-window-height", load: { config.scrolling.keepWindowHeight }) private var scrollingKeepWindowHeight: Bool
    @SettingsDraft("scrolling.center-focused-column", load: { config.scrolling.centerFocusedColumn }) private var scrollingCenterMode: ScrollingCenterMode
    @SettingsDraft("scrolling.minimap-hold-modifiers", load: { minimapHoldModifierNames(config.scrolling.minimapHoldModifiers) }) private var minimapHoldModifiers: String
    @SettingsDraft("automatically-tile-new-windows", load: { config.automaticallyTileNewWindows }) private var automaticallyTileNewWindows: Bool
    @State private var confirmsForgetAllMinimums = false
    @State private var showsLearnedMinimums = false
    @State private var showsCustomColumnSizes = false
    @State private var showsAdvancedNavigation = false

    @SettingsDraft("single-window-alignment", load: { config.singleWindowAlignment }) private var singleWindowAlignment: SingleWindowAlignment
    @SettingsDraft("fullscreen-width", load: { config.fullscreenWidth ?? 1.0 }) private var fullscreenWidth: Double

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", id: "automatically-tile-new-windows", isOn: $automaticallyTileNewWindows, help: "A new window becomes a column right of the focused one. Off leaves new windows floating.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
            }
            SettingsSection("Single window and managed fullscreen") {
                SettingsStepper("Single-window width", id: "fullscreen-width", value: Binding(
                    get: { Int((fullscreenWidth * 100).rounded()) },
                    set: { fullscreenWidth = Double($0) / 100 }), range: 10...100,
                    help: "Share of the available width for a lone tiled window or StripMuxX fullscreen. Display overrides take priority.", unit: "%") {
                    persistConfig(section: nil, key: "fullscreen-width", value: String(fullscreenWidth))
                }
                Text("Also used by managed fullscreen. Choose 100% to maximize within the usable display area; native macOS fullscreen is separate.")
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
            scrollingSettingsSection
            DisclosureGroup("Advanced: learned application minimums", isExpanded: $showsLearnedMinimums) {
                learnedMinimumsSection
            }
        }
        .navigationTitle("Windows")
        .confirmationDialog("Forget all learned minimum sizes?", isPresented: $confirmsForgetAllMinimums, titleVisibility: .visible) {
            Button("Forget All", role: .destructive) { minimums.forgetAll() }
        } message: {
            Text("StripMuxX will relearn app minimums from future resize attempts.")
        }

    }

    private var learnedMinimumsSection: some View {
        SettingsSection("Learned minimum sizes (diagnostics)") {
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
        Group {
            SettingsSection("Columns") {
                SettingsColumnWidthPicker(value: $scrollingColumnWidth) {
                    persistConfig(section: "scrolling", key: "column-width",
                                  value: String(Double(scrollingColumnWidth) / 100))
                }
                SettingsColumnPresetPicker(values: Binding(
                    get: { scrollingPresetValues(scrollingWidthPresets) ?? config.scrolling.widthPresets },
                    set: { values in
                        scrollingWidthPresets = values.map { String($0 * 100) }.joined(separator: ", ")
                        persistConfig(section: "scrolling", key: "width-presets",
                                      value: "[" + values.map(String.init).joined(separator: ", ") + "]")
                    }))
                DisclosureGroup("Custom column sizes", isExpanded: $showsCustomColumnSizes) {
                    SettingsStepper("Exact default width", id: "scrolling.column-width.custom",
                                    value: $scrollingColumnWidth, range: 10...100,
                                    help: "Use any whole percentage, including values between the illustrated cards.", unit: "%") {
                        persistConfig(section: "scrolling", key: "column-width",
                                      value: String(Double(scrollingColumnWidth) / 100))
                    }
                    SettingsTextField("Exact size shortcuts (%)", id: "scrolling.width-presets.custom",
                                      text: $scrollingWidthPresets,
                                      help: "Ascending percentages from 10 to 100; keeps custom sizes.",
                                      validate: scrollingPresetError) {
                        if let values = scrollingPresetValues(scrollingWidthPresets) {
                            persistConfig(section: "scrolling", key: "width-presets",
                                          value: "[" + values.map(String.init).joined(separator: ", ") + "]")
                        }
                    }
                }
            }
            SettingsSection("Navigation") {
                SettingsToggle("Option + two-finger pan", id: "scrolling.gesture-enabled",
                               isOn: $scrollingGestureEnabled,
                               help: "Two-finger scrolling without Option remains in the application.") {
                    persistConfig(section: "scrolling", key: "gesture-enabled",
                                  value: scrollingGestureEnabled ? "true" : "false")
                }
                SettingsToggle("Three-finger pan (experimental)", id: "scrolling.three-finger-swipe",
                               isOn: $threeFingerSwipe,
                               help: "Uses undocumented macOS Dock swipe events. Requires three-finger Space swipes in Trackpad settings.") {
                    persistConfig(section: "scrolling", key: "three-finger-swipe",
                                  value: threeFingerSwipe ? "true" : "false")
                }
                .disabled(!scrollingGestureEnabled)
                SettingsPicker("When focusing a column", id: "scrolling.center-focused-column",
                               selection: $scrollingCenterMode,
                               help: "Choose how the strip moves when keyboard focus changes.") {
                    Text("Reveal only (recommended)").tag(ScrollingCenterMode.never)
                    Text("Center if offscreen").tag(ScrollingCenterMode.onOverflow)
                    Text("Always center").tag(ScrollingCenterMode.always)
                } onChange: {
                    persistConfig(section: "scrolling", key: "center-focused-column",
                                  value: "'\(scrollingCenterMode.rawValue)'")
                }
                DisclosureGroup("Advanced navigation", isExpanded: $showsAdvancedNavigation) {
                    SettingsTextField("Gesture sensitivity", id: "scrolling.gesture-sensitivity",
                                      text: $scrollingSensitivity,
                                      help: "Positive movement multiplier.", validate: scrollingSensitivityError) {
                        if let value = Double(scrollingSensitivity), value.isFinite, value > 0 {
                            persistConfig(section: "scrolling", key: "gesture-sensitivity", value: String(value))
                        }
                    }
                    SettingsToggle("Keep opening window height", id: "scrolling.keep-window-height",
                                   isOn: $scrollingKeepWindowHeight,
                                   help: "A window alone in a column retains its original height.") {
                        persistConfig(section: "scrolling", key: "keep-window-height",
                                      value: scrollingKeepWindowHeight ? "true" : "false")
                    }
                }
            }
            SettingsSection("Minimap") {
                SettingsToggle("Show scrolling minimap", id: "scrolling.minimap-enabled",
                               isOn: $scrollingMinimapEnabled,
                               help: "Visualize and navigate the strip with a gesture or keyboard shortcut.") {
                    persistConfig(section: "scrolling", key: "minimap-enabled",
                                  value: scrollingMinimapEnabled ? "true" : "false")
                }
                SettingsStepper("Offscreen column preview", id: "scrolling.edge-preview",
                                value: $edgePreview, range: 0...40,
                                help: "Visible edge of a column outside the current viewport.", unit: "pt") {
                    persistConfig(section: "scrolling", key: "edge-preview", value: String(edgePreview))
                }
                SettingsTextField("Hold to show minimap", id: "scrolling.minimap-hold-modifiers",
                                  text: $minimapHoldModifiers,
                                  help: "Optional keys: ctrl, alt, cmd, shift; empty turns this off.",
                                  validate: minimapHoldModifierError) {
                    if minimapHoldModifierError(minimapHoldModifiers) == nil {
                        persistConfig(section: "scrolling", key: "minimap-hold-modifiers",
                                      value: tomlCommaSeparatedStringArray(minimapHoldModifiers))
                    }
                }
                .disabled(!scrollingMinimapEnabled)
            }
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
