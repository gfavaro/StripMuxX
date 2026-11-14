import SwiftUI

struct ShortcutGeneralSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("start-at-login", load: { config.startAtLogin }) private var startAtLogin: Bool
    @SettingsDraft("auto-reload-config", load: { config.autoReloadConfig }) private var autoReloadConfig: Bool
    @State private var advancedOpen = false

    @SettingsDraft("native-spaces.restore-layouts", load: { config.nativeSpaces.restoreLayouts }) private var restoreNativeLayouts: Bool
    @SettingsDraft("native-spaces.restore-frames-on-quit", load: { config.nativeSpaces.restoreFramesOnQuit }) private var restoreFramesOnQuit: Bool
    var body: some View {
        SettingsScrollView {
            SettingsSection("Startup") {
                SettingsToggle("Start at login", id: "start-at-login", isOn: $startAtLogin, help: "Launch StripMuxX after you sign in.") {
                    persistRootBool("start-at-login", startAtLogin)
                }
            }
            SettingsSection("Desktops") {
                SettingsToggle("Restore strips", id: "native-spaces.restore-layouts", isOn: $restoreNativeLayouts, help: "Remember each desktop's strip and put it back after StripMuxX or the Mac restarts.") {
                    persistSettingsConfig(section: "native-spaces", key: "restore-layouts", renderedValue: restoreNativeLayouts ? "true" : "false", model: model)
                }
                SettingsToggle("Put windows back on quit", id: "native-spaces.restore-frames-on-quit", isOn: $restoreFramesOnQuit, help: "Quitting StripMuxX or turning it off returns tiled windows on the desktops showing to where they were before tiling.") {
                    persistSettingsConfig(section: "native-spaces", key: "restore-frames-on-quit", renderedValue: restoreFramesOnQuit ? "true" : "false", model: model)
                }
            }
            DisclosureGroup("Advanced setup", isExpanded: $advancedOpen) {
                SettingsToggle("Reload config automatically", id: "auto-reload-config",
                               isOn: $autoReloadConfig,
                               help: "Apply valid changes made in an external TOML editor.") {
                    persistRootBool("auto-reload-config", autoReloadConfig)
                }
                SetupCheckView()
            }
            SettingsSection("Troubleshooting") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics")
                        Text("Permissions, displays and tiling state, with a button to copy the report for a bug report.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Diagnostics…") { DiagnosticsWindowController.shared.show() }
                }
            }
        }
        .navigationTitle("General")

    }

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistSettingsConfig(section: nil, key: key, renderedValue: value ? "true" : "false", model: model)
    }
}
