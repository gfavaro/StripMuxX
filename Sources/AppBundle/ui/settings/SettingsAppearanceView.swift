import SwiftUI

struct ShortcutAppearanceSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("appearance", load: { config.appearance }) private var appearance: AppAppearance
    @SettingsDraft("menu-bar.indicator", load: { config.menuBar.indicator }) private var menuBarIndicator: MenuBarIndicator
    @SettingsDraft("menu-bar.icon-appearance", load: { config.menuBar.iconAppearance }) private var menuBarIconAppearance: MenuBarIconAppearance
    @SettingsDraft("gaps.inner.horizontal", load: { settingsConstantValue(config.gaps.inner.horizontal) }) private var innerHorizontalGap: Int
    @SettingsDraft("gaps.inner.vertical", load: { settingsConstantValue(config.gaps.inner.vertical) }) private var innerVerticalGap: Int
    @SettingsDraft("gaps.outer.left", load: { settingsConstantValue(config.gaps.outer.left) }) private var outerLeftGap: Int
    @SettingsDraft("gaps.outer.right", load: { settingsConstantValue(config.gaps.outer.right) }) private var outerRightGap: Int
    @SettingsDraft("gaps.outer.top", load: { settingsConstantValue(config.gaps.outer.top) }) private var outerTopGap: Int
    @SettingsDraft("gaps.outer.bottom", load: { settingsConstantValue(config.gaps.outer.bottom) }) private var outerBottomGap: Int

    @State private var showsInnerSpacing = false
    @State private var showsOuterSpacing = false
    @Environment(\.settingsSearchTarget) private var searchTarget

    var body: some View {
        SettingsScrollView {
            SettingsSection("Theme") {
                SettingsPicker("Theme", id: "appearance", selection: $appearance,
                               help: "Apply System, Light or Dark to StripMuxX's own windows.") {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                } onChange: { persist(nil, "appearance", "'\(appearance.rawValue)'") }


            }
            SettingsSection("Menu bar") {
                SettingsPicker("Menu bar indicator", id: "menu-bar.indicator", selection: $menuBarIndicator,
                               help: "Desktop shows the number of the focused display's desktop.") {
                    Text("Icon").tag(MenuBarIndicator.icon)
                    Text("Desktop").tag(MenuBarIndicator.workspace)
                } onChange: {
                    persist("menu-bar", "indicator", "'\(menuBarIndicator.rawValue)'")
                }
                if menuBarIndicator == .icon {
                    SettingsPicker("Icon appearance", id: "menu-bar.icon-appearance", selection: $menuBarIconAppearance,
                                   help: "Color uses the system accent; monochrome follows the menu bar. Keyboard modes tint either icon.") {
                        ForEach(MenuBarIconAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    } onChange: {
                        persist("menu-bar", "icon-appearance", "'\(menuBarIconAppearance.rawValue)'")
                    }
                }
            }



            SettingsSection("Window spacing") {
                if hasPerMonitorGaps {
                    Text("These values edit the default spacing. Per-display overrides in your config are preserved.")
                    .font(.callout).foregroundStyle(.secondary)
                }
                SettingsGapPreview(values: SettingsGapPreviewValues(horizontal: innerHorizontalGap, vertical: innerVerticalGap,
                    left: outerLeftGap, right: outerRightGap, top: outerTopGap, bottom: outerBottomGap))
                DisclosureGroup("Space between windows", isExpanded: $showsInnerSpacing) {
                    SettingsGapSlider(id: "gaps.inner.horizontal", title: "Horizontal", value: $innerHorizontalGap, range: 0...80,
                        help: "Space between windows side by side.", savedValue: settingsConstantValue(config.gaps.inner.horizontal)) {
                        persist("gaps", "inner.horizontal", settingsGapValue(config.gaps.inner.horizontal, replacingDefaultWith: innerHorizontalGap))
                    }
                    SettingsGapSlider(id: "gaps.inner.vertical", title: "Vertical", value: $innerVerticalGap, range: 0...80,
                        help: "Space between vertically stacked windows.", savedValue: settingsConstantValue(config.gaps.inner.vertical)) {
                        persist("gaps", "inner.vertical", settingsGapValue(config.gaps.inner.vertical, replacingDefaultWith: innerVerticalGap))
                    }
                }
                DisclosureGroup("Space around windows", isExpanded: $showsOuterSpacing) {
                    SettingsGapSlider(id: "gaps.outer.left", title: "Left", value: $outerLeftGap, range: 0...120,
                        help: "Space from the left display edge.", savedValue: settingsConstantValue(config.gaps.outer.left)) {
                        persist("gaps", "outer.left", settingsGapValue(config.gaps.outer.left, replacingDefaultWith: outerLeftGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.right", title: "Right", value: $outerRightGap, range: 0...120,
                        help: "Space from the right display edge.", savedValue: settingsConstantValue(config.gaps.outer.right)) {
                        persist("gaps", "outer.right", settingsGapValue(config.gaps.outer.right, replacingDefaultWith: outerRightGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.top", title: "Top", value: $outerTopGap, range: 0...120,
                        help: "Space from the top of the usable display area.", savedValue: settingsConstantValue(config.gaps.outer.top)) {
                        persist("gaps", "outer.top", settingsGapValue(config.gaps.outer.top, replacingDefaultWith: outerTopGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.bottom", title: "Bottom", value: $outerBottomGap, range: 0...120,
                        help: "Space from the bottom display edge.", savedValue: settingsConstantValue(config.gaps.outer.bottom)) {
                        persist("gaps", "outer.bottom", settingsGapValue(config.gaps.outer.bottom, replacingDefaultWith: outerBottomGap))
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .onAppear { revealSearchedGap() }
        .onChange(of: searchTarget) { _ in revealSearchedGap() }
    }

    private func revealSearchedGap() {
        guard let id = searchTarget?.id else { return }
        if id.hasPrefix("gaps.inner.") { showsInnerSpacing = true }
        if id.hasPrefix("gaps.outer.") { showsOuterSpacing = true }
    }

    private var hasPerMonitorGaps: Bool {
        [config.gaps.inner.horizontal, config.gaps.inner.vertical, config.gaps.outer.left,
        config.gaps.outer.right, config.gaps.outer.top, config.gaps.outer.bottom].contains {
            if case .perMonitor = $0 { return true }
            return false
        }
    }

    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}

private func settingsConstantValue(_ value: DynamicConfigValue<Int>) -> Int {
    switch value {
        case .constant(let value): value
        case .perMonitor(_, let `default`): `default`
    }
}
