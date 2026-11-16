import AppKit
import Common
import SwiftUI

/// One thing StripMuxX needs from macOS, and how to fix it when it is missing.
struct SetupCheckItem: Equatable, Identifiable {
    let id: String
    let title: String
    let ok: Bool
    let detail: String
    var fixURL: String? = nil
}

/// What the checks read, so tests can supply it.
struct SetupCheckInput {
    var accessibilityGranted: Bool
    var otherWindowManagers: [String]
    /// macOS "Displays have separate Spaces" (`spans-displays` off).
    var separateSpaces: Bool
    /// macOS "Automatically rearrange Spaces based on most recent use".
    var rearrangesSpaces: Bool

    @MainActor static var current: Self {
        return Self(
            accessibilityGranted: AXIsProcessTrusted(),
            otherWindowManagers: runningOtherWindowManagers(),
            separateSpaces: !(CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString) as? Bool ?? false),
            rearrangesSpaces: CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString) as? Bool ?? true,
        )
    }
}

private let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
private let desktopSettings = "x-apple.systempreferences:com.apple.Desktop-Settings.extension"

func setupCheckItems(_ input: SetupCheckInput) -> [SetupCheckItem] {
    var items = [
        SetupCheckItem(id: "accessibility", title: "Accessibility permission", ok: input.accessibilityGranted,
                       detail: input.accessibilityGranted ? "Granted." : "StripMuxX cannot move or resize windows without it. Turn on StripMuxX in Privacy & Security › Accessibility.",
                       fixURL: input.accessibilityGranted ? nil : accessibilitySettings),
        SetupCheckItem(id: "other-window-managers", title: "No other window manager", ok: input.otherWindowManagers.isEmpty,
                       detail: input.otherWindowManagers.isEmpty ? "None running." : "\(input.otherWindowManagers.joined(separator: ", ")) also moves windows; quit it so the two do not fight."),
    ]
    items.append(SetupCheckItem(id: "separate-spaces", title: "Displays have separate Spaces", ok: input.separateSpaces,
        detail: input.separateSpaces ? "On." : "Each display's own space gets a strip. Turn on Displays have separate Spaces in Desktop & Dock, then log out and back in.",
        fixURL: input.separateSpaces ? nil : desktopSettings))
    items.append(SetupCheckItem(id: "rearrange-spaces", title: "Spaces keep their order", ok: !input.rearrangesSpaces,
        detail: input.rearrangesSpaces ? "macOS reorders spaces by recent use, so space numbers and shortcuts change. Turn off Automatically rearrange Spaces based on most recent use in Desktop & Dock." : "Off.",
        fixURL: input.rearrangesSpaces ? desktopSettings : nil))
    return items
}

/// Opens Settings › General once when something needs attention.
@MainActor func showSetupCheckIfNeeded() {
    guard !isUnitTest else { return }
    let key = "setupCheck.shown.native"
    guard !UserDefaults.standard.bool(forKey: key), setupCheckItems(.current).contains(where: { !$0.ok }) else { return }
    UserDefaults.standard.set(true, forKey: key)
    UserDefaults.standard.set(SettingsSidebarItem.general.rawValue, forKey: "settings.selectedPage")
    ShortcutSettingsModel.shared.requestWindowOpen()
}

struct SetupCheckView: View {
    @State private var items: [SetupCheckItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.ok ? .green : .orange)
                        .accessibilityLabel(item.ok ? "OK" : "Needs attention")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let fix = item.fixURL.flatMap(URL.init(string:)) {
                        Button("Open Settings") { NSWorkspace.shared.open(fix) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Check Again") { items = setupCheckItems(.current) }
            }
        }
        .onAppear { items = setupCheckItems(.current) }
    }
}
