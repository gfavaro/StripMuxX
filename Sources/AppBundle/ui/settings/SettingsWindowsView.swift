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
    @SettingsDraft("scrolling.minimap-enabled", load: { config.scrolling.minimapEnabled }) private var scrollingMinimapEnabled: Bool
    @SettingsDraft("scrolling.keep-window-height", load: { config.scrolling.keepWindowHeight }) private var scrollingKeepWindowHeight: Bool
    @SettingsDraft("scrolling.center-focused-column", load: { config.scrolling.centerFocusedColumn }) private var scrollingCenterMode: ScrollingCenterMode
    @SettingsDraft("scrolling.minimap-hold-modifiers", load: { minimapHoldModifierNames(config.scrolling.minimapHoldModifiers) }) private var minimapHoldModifiers: String
    @SettingsDraft("automatically-tile-new-windows", load: { config.automaticallyTileNewWindows }) private var automaticallyTileNewWindows: Bool
    @State private var confirmsForgetAllMinimums = false
    @State private var showsLearnedMinimums = false
    @State private var showsCustomColumnSizes = false
    @State private var showsAdvancedNavigation = false
    @State private var showsSingleWindowOptions = false
    @Environment(\.settingsSearchTarget) private var searchTarget

    @SettingsDraft("single-window-alignment", load: { config.singleWindowAlignment }) private var singleWindowAlignment: SingleWindowAlignment
    @SettingsDraft("single-window-aspect-ratio", load: { String(config.singleWindowAspectRatio) }) private var singleWindowRatio: String

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", id: "automatically-tile-new-windows", isOn: $automaticallyTileNewWindows, help: "A new window becomes a column right of the focused one. Off leaves new windows floating.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
            }
            scrollingSettingsSection
            DisclosureGroup("Single-window shape", isExpanded: $showsSingleWindowOptions) {
                SettingsSection("When one window is open") {

                SettingsTextField("Lone window aspect ratio", id: "single-window-aspect-ratio", text: $singleWindowRatio,
                                  help: "A window alone on a desktop is at most this many times as wide as it is tall, so it keeps the same shape on any display. 0 lets it fill the width; 1.6 is a 16:10 window.",
                                  validate: singleWindowRatioError) {
                    if let value = parseSingleWindowRatio(singleWindowRatio) {
                        persistConfig(section: nil, key: "single-window-aspect-ratio", value: String(value))
                    }
                }
                Text("Per-display ratios and alignment can be set in [display.<name>] tables. Native macOS fullscreen creates a separate Space; StripMuxX fullscreen fills the display.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsLoneWindowPreview(ratio: parseSingleWindowRatio(singleWindowRatio) ?? defaultSingleWindowAspectRatio,
                                          alignment: singleWindowAlignment)
                    .padding(.vertical, 4)
                SettingsPicker("Alignment", id: "single-window-alignment", selection: $singleWindowAlignment,
                    help: "Position a lone tiled window within the available area after gaps.") {
                    Text("Centered").tag(SingleWindowAlignment.center)
                    Text("Left").tag(SingleWindowAlignment.left)
                    Text("Right").tag(SingleWindowAlignment.right)
                } onChange: { persistRootString("single-window-alignment", singleWindowAlignment.rawValue) }
                }
            }
            DisclosureGroup("Advanced: learned application minimums", isExpanded: $showsLearnedMinimums) {
                learnedMinimumsSection
            }
        }
        .navigationTitle("Windows")
        .onAppear { revealSearchedControl() }
        .onChange(of: searchTarget) { _ in revealSearchedControl() }
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
            columnsSection
            navigationSection
            minimapSection
        }
    }

    // Separate properties keep each body small enough for the type checker.
    private var columnsSection: some View {
            SettingsSection("Columns") {
                SettingsColumnWidthPicker(value: $scrollingColumnWidth) {
                    persistConfig(section: "scrolling", key: "column-width",
                                  value: String(Double(scrollingColumnWidth) / 100))
                }
                SettingsColumnPresetPicker(values: presetValuesBinding)
                SettingsStepper("Offscreen column preview", id: "scrolling.edge-preview",
                                value: $edgePreview, range: 0...40,
                                help: "Visible edge of a column outside the current viewport.", unit: "pt") {
                    persistConfig(section: "scrolling", key: "edge-preview", value: String(edgePreview))
                }
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
                        if let values = scrollingPresetValues(scrollingWidthPresets) { persistWidthPresets(values) }
                    }
                }
            }
    }

    private var presetValuesBinding: Binding<[Double]> {
        Binding<[Double]>(
            get: { scrollingPresetValues(scrollingWidthPresets) ?? config.scrolling.widthPresets },
            set: { (values: [Double]) in
                scrollingWidthPresets = values.map { (value: Double) in String(value * 100) }.joined(separator: ", ")
                persistWidthPresets(values)
            })
    }

    private func persistWidthPresets(_ values: [Double]) {
        let rendered: String = "[" + values.map { (value: Double) in String(value) }.joined(separator: ", ") + "]"
        persistConfig(section: "scrolling", key: "width-presets", value: rendered)
    }

    private var navigationSection: some View {
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
                    SettingsToggle("Keep opening window height", id: "scrolling.keep-window-height",
                                   isOn: $scrollingKeepWindowHeight,
                                   help: "A window alone in a column retains its original height.") {
                        persistConfig(section: "scrolling", key: "keep-window-height",
                                      value: scrollingKeepWindowHeight ? "true" : "false")
                    }
                }
            }
    }

    private var minimapSection: some View {
            SettingsSection("Minimap") {
                SettingsToggle("Show scrolling minimap", id: "scrolling.minimap-enabled",
                               isOn: $scrollingMinimapEnabled,
                               help: "Visualize and navigate the strip with a gesture or keyboard shortcut.") {
                    persistConfig(section: "scrolling", key: "minimap-enabled",
                                  value: scrollingMinimapEnabled ? "true" : "false")
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

    private func revealSearchedControl() {
        switch searchTarget?.id {
            case "single-window-aspect-ratio", "single-window-alignment":
                showsSingleWindowOptions = true
            case "scrolling.width-presets.custom", "scrolling.column-width.custom":
                showsCustomColumnSizes = true
            default: break
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

func parseSingleWindowRatio(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite, (0...6).contains(value) else { return nil }
    return value
}

private func singleWindowRatioError(_ text: String) -> String? {
    parseSingleWindowRatio(text) == nil ? "Enter a number from 0 (fill the width) to 6, such as 1.6." : nil
}

/// Where a lone window sits in a preview of the display: as wide as `ratio` times its height, at most the full width.
func settingsLoneWindowPreviewFrame(in bounds: CGRect, ratio: Double, alignment: SingleWindowAlignment) -> CGRect {
    let width = ratio > 0 ? min(bounds.width, bounds.height * CGFloat(ratio)) : bounds.width
    let x: CGFloat
    switch alignment {
        case .left: x = bounds.minX
        case .right: x = bounds.maxX - width
        case .center: x = bounds.midX - width / 2
    }
    return CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
}

/// Noninteractive diagram showing how a single tiled column is positioned.
private struct SettingsLoneWindowPreview: View {
    let ratio: Double
    let alignment: SingleWindowAlignment
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Single-window preview").font(.caption.weight(.medium))
            GeometryReader { geometry in
                let area = CGRect(x: 8, y: 8, width: max(geometry.size.width - 16, 0),
                                  height: max(geometry.size.height - 16, 0))
                let window = settingsLoneWindowPreviewFrame(in: area, ratio: ratio, alignment: alignment)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .frame(width: window.width, height: window.height)
                        .position(x: window.midX, y: window.midY)
                }
            }
            .frame(height: 76)
            .accessibilityHidden(true)
            SettingsDescription("Illustration only; display-specific overrides may differ.")
        }
    }
}
