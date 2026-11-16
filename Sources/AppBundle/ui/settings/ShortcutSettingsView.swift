import AppKit
import Common
import MASShortcut
import SwiftUI

// Measured from System Settings on macOS 27: resizable settings window.
let settingsWindowWidth: CGFloat = 757
let settingsWindowMinimumHeight: CGFloat = 470

public let shortcutSettingsWindowId = "\(winMuxAppName).shortcutSettings"

@MainActor
public func getShortcutSettingsWindow(model: ShortcutSettingsModel) -> some Scene {
    SwiftUI.Window("StripMuxX Settings", id: shortcutSettingsWindowId) {
        ShortcutSettingsWindowContent(model: model)
            .frame(minWidth: settingsWindowWidth,
                   minHeight: settingsWindowMinimumHeight, maxHeight: .infinity)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                // SwiftUI may materialize a Window scene during app launch even
                // when no openWindow request was made. Settings is opt-in, so
                // dismiss that implicit scene and keep explicit requests intact.
                if model.openRequestId == 0 {
                    DispatchQueue.main.async {
                        shortcutSettingsWindow()?.close()
                    }
                } else if !model.isWindowShown {
                    // An open was requested (first run's setup check asks at startup) before this
                    // scene observed it, so its pages were never switched on and the window
                    // would stay an empty placeholder.
                    showRequestedSettingsWindow()
                }
            }
    }
    .defaultSize(width: settingsWindowWidth, height: 700)
    .windowResizability(.contentSize)
}

/// The window exists because an open was requested; turn its pages on and bring it forward.
@MainActor
func showRequestedSettingsWindow() {
    ShortcutSettingsModel.shared.reload()
    ShortcutSettingsModel.shared.isWindowShown = true
    _ = releaseSettingsPagesOnClose
    DispatchQueue.main.async {
        if let window = shortcutSettingsWindow() { presentShortcutSettingsWindow(window) }
    }
}

@MainActor
public func openShortcutSettingsWindow(_ openWindow: OpenWindowAction) {
    ShortcutSettingsModel.shared.reload()
    ShortcutSettingsModel.shared.isWindowShown = true
    _ = releaseSettingsPagesOnClose
    if let existingWindow = shortcutSettingsWindow() {
        presentShortcutSettingsWindow(existingWindow)
    } else {
        openWindow(id: shortcutSettingsWindowId)
        DispatchQueue.main.async {
            if let createdWindow = shortcutSettingsWindow() {
                presentShortcutSettingsWindow(createdWindow)
            }
        }
    }
}

/// SwiftUI keeps a closed Window scene, and it builds this one at launch even when
/// Settings is never opened, so every page used to stay in memory for the app's life.
@MainActor
private let releaseSettingsPagesOnClose: Void = {
    _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
        // Delivered on the main queue, so the window is only ever touched on the main actor.
        let closing = note.object as? NSWindow
        MainActor.assumeIsolated {
            guard closing?.identifier?.rawValue == shortcutSettingsWindowId else { return }
            ShortcutSettingsModel.shared.isWindowShown = false
        }
    }
}()

/// Holds the pages while the window is open. The rule and display editors live here so
/// their unsaved edits outlast a close, like the other setting drafts.
struct ShortcutSettingsWindowContent: View {
    @ObservedObject var model: ShortcutSettingsModel
    @StateObject private var displays = SettingsDisplaysModel()
    @StateObject private var rules = SettingsWindowRulesModel()

    var body: some View {
        if model.isWindowShown {
            ShortcutSettingsView(model: model, displays: displays, rules: rules)
        } else {
            Color.clear
        }
    }
}

enum SettingsSidebarItem: String, Hashable, Identifiable, CaseIterable {
    case general
    case shortcuts
    case workspaces
    case displays
    case appearance
    case windows
    case automation
    case configuration

    static func restored(_ value: String) -> Self { Self(rawValue: value) ?? .general }

    var id: Self { self }
    var isAdvanced: Bool { self == .configuration || self == .automation }

    var label: String {
        switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .workspaces: "Desktops"
            case .displays: "Displays"
            case .windows: "Windows"
            case .appearance: "Appearance"
            case .automation: "Automation"
            case .configuration: "Configuration"
        }
    }

    var icon: String {
        switch self {
            case .general: "gearshape"
            case .shortcuts: "keyboard"
            case .workspaces: "rectangle.3.group"
            case .displays: "display.2"
            case .windows: "macwindow.on.rectangle"
            case .appearance: "paintpalette"
            case .automation: "gearshape.2"
            case .configuration: "doc.text"
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var displays: SettingsDisplaysModel
    @ObservedObject var rules: SettingsWindowRulesModel
    @AppStorage("settings.selectedPage") private var storedPage = SettingsSidebarItem.general.rawValue
    @State private var shortcutSearch = ""
    @State private var settingsSearch = ""
    @State private var searchTarget: SettingsSearchDestination?
    @State private var selectedControl: SettingsControl?
    @State private var showsAdvanced = false

    private var selectedItem: SettingsSidebarItem? {
        get { SettingsSidebarItem.restored(storedPage) }
        nonmutating set {
            if let newValue {
                searchTarget = nil
                selectedControl = nil
                storedPage = newValue.rawValue
            }
        }
    }
    private var selection: Binding<SettingsSidebarSelection?> {
        Binding(get: { selectedControl.map { .control($0) } ?? selectedItem.map { .page($0) } },
                set: { choose($0) })
    }

    private func choose(_ destination: SettingsSidebarSelection?) {
        switch destination {
            case .page(let page): selectedItem = page
            case .control(let control):
                selectedItem = control.page
                searchTarget = SettingsSearchDestination(id: control.id)
                selectedControl = control
            case nil: break
        }
    }

    private let sidebarItems: [SettingsSidebarItem] = [.general, .workspaces, .displays, .windows, .appearance, .shortcuts, .automation, .configuration]

    var body: some View {
        let hasQuery = !settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let controls = settingsControlSearchResults(settingsSearch)
        let pages = settingsPageSearchResults(settingsSearch, pages: sidebarItems)
        NavigationSplitView {
            List(selection: selection) {
                if hasQuery {
                    Section("Settings") {
                        ForEach(controls) { control in
                            NavigationLink(value: SettingsSidebarSelection.control(control)) {
                                VStack(alignment: .leading) {
                                    Text(control.title)
                                    Text(control.page.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Get started") {
                    ForEach([SettingsSidebarItem.general, .windows, .shortcuts].filter { pages.contains($0) }) { item in
                        NavigationLink(value: SettingsSidebarSelection.page(item)) {
                            Label(item.label, systemImage: item.icon)
                        }
                    }
                }
                Section("Organize") {
                    ForEach([SettingsSidebarItem.workspaces, .displays].filter { pages.contains($0) }) { item in
                        NavigationLink(value: SettingsSidebarSelection.page(item)) {
                            Label(item.label, systemImage: item.icon)
                        }
                    }
                }
                Section("Personalize") {
                    ForEach([SettingsSidebarItem.appearance].filter { pages.contains($0) }) { item in
                        NavigationLink(value: SettingsSidebarSelection.page(item)) {
                            Label(item.label, systemImage: item.icon)
                        }
                    }
                }
                if hasQuery {
                    Section("Advanced") {
                        ForEach(pages.filter(\.isAdvanced)) { item in
                            NavigationLink(value: SettingsSidebarSelection.page(item)) {
                                Label(item.label, systemImage: item.icon)
                            }
                        }
                    }
                    if pages.isEmpty && controls.isEmpty {
                        Text("No matching settings").foregroundStyle(.secondary)
                    }
                } else {
                    DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                        ForEach(sidebarItems.filter(\.isAdvanced)) { item in
                            NavigationLink(value: SettingsSidebarSelection.page(item)) {
                                Label(item.label, systemImage: item.icon)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                SettingsSearchField(text: $settingsSearch) {
                    choose(settingsSearchSubmitSelection(controls: controls, pages: pages))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .onAppear { showsAdvanced = selectedItem?.isAdvanced == true }
            .onChange(of: storedPage) { _ in if selectedItem?.isAdvanced == true { showsAdvanced = true } }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSaveSummary(model: model, additionalUnsaved: rules.isDirty || displays.assignment.isDirty).padding(.horizontal, 20)
                Group {
                switch selectedItem {
                    case .general:
                        ShortcutGeneralSettingsView(model: model)
                    case .shortcuts:
                        ShortcutSettingsShortcutsView(model: model, query: $shortcutSearch)
                    case .workspaces:
                        ShortcutSettingsWorkspacePane(model: model)
                    case .displays:
                        SettingsDisplaysView(model: model, displays: displays, onGeneral: { selectedItem = .general })
                    case .windows:
                        ShortcutBehaviorSettingsView(model: model)
                    case .appearance:
                        ShortcutAppearanceSettingsView(model: model)

                    case .automation:
                        ShortcutAutomationSettingsView(model: model, rules: rules, onRawEditor: { selectedItem = .configuration })
                    case .configuration:
                        SettingsConfigurationView(model: model, onNavigate: { selectedItem = $0 })
                    case nil:
                        Text("Select an item")
                }
                }
            }

            .environment(\.settingsSearchTarget, searchTarget)
            .onChange(of: settingsSearch) { _ in searchTarget = nil; selectedControl = nil }
            .navigationTitle(selectedItem?.label ?? "")
        }
    }
}

struct ShortcutSettingsShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @Binding var query: String

    var body: some View {
        ShortcutCategoryView(model: model, category: .managed, query: $query)
    }
}

struct ShortcutSettingsWorkspacePane: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        ShortcutCategoryView(model: model, category: .common)
    }
}

struct ShortcutCategoryView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let category: ShortcutSettingsModel.Category
    @Binding var query: String

    init(model: ShortcutSettingsModel, category: ShortcutSettingsModel.Category, query: Binding<String> = .constant("")) {
        self.model = model; self.category = category; self._query = query
    }
    @SettingsDraft("modifiers.alt", load: { config.modifierSides.alt.rawValue }) private var altSide: String
    @SettingsDraft("modifiers.cmd", load: { config.modifierSides.cmd.rawValue }) private var cmdSide: String
    @SettingsDraft("modifiers.ctrl", load: { config.modifierSides.ctrl.rawValue }) private var ctrlSide: String
    @SettingsDraft("modifiers.shift", load: { config.modifierSides.shift.rawValue }) private var shiftSide: String
    @SettingsDraft("persistent-workspaces", load: { config.persistentWorkspaces.joined(separator: ", ") }) private var persistentWorkspaces: String

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Form {
            if category == .managed {
                Section {
                    HStack {
                        TextField("Search shortcuts", text: $query, prompt: Text("Action, command or shortcut"))
                            .accessibilityIdentifier("settings.shortcuts.search")
                        if !query.isEmpty { Button("Clear") { query = "" }.accessibilityLabel("Clear shortcut search") }
                    }
                }
            }

            if category == .common {
                Section("Desktops kept") {
                    SettingsTextField("Desktop numbers", id: "persistent-workspaces", text: $persistentWorkspaces,
                        help: "Comma-separated desktop numbers, for example 1, 2, 3. StripMuxX adds macOS desktops until the highest number exists.") {
                        persistSettingsConfig(section: nil, key: "persistent-workspaces",
                            renderedValue: tomlCommaSeparatedStringArray(persistentWorkspaces), model: model)
                    }
                    SettingsDescription("Desktops are macOS Spaces: create, remove and reorder them in Mission Control. StripMuxX only adds missing ones, and never removes any.")
                }
            }

            if category == .managed && !searching {
                SettingsModeOptionsView(model: model)
                Section("Modifier keys") {
                    modifierSidePicker("Option", key: "alt", selection: $altSide)
                    modifierSidePicker("Command", key: "cmd", selection: $cmdSide)
                    modifierSidePicker("Control", key: "ctrl", selection: $ctrlSide)
                    modifierSidePicker("Shift", key: "shift", selection: $shiftSide)
                    SettingsDescription("Choose which side triggers shortcuts. The other side passes through for typing. Modifier-only taps keep their explicit left/right bindings.")
                }
            }

            let candidates = model.sections.filter { $0.category == category && (searching || $0.id != "managed-move") }
            let sections = filteredShortcutSections(candidates, assignments: model.assignments, query: query)
            ForEach(sections) { section in
                if searching {
                    Section(section.title) {
                        ForEach(section.actions) { action in ShortcutRow(model: model, action: action) }
                    }
                } else {
                    ShortcutSectionView(model: model, section: section)
                }
            }
            if searching && sections.isEmpty {
                Section {
                    Text("No matching shortcuts").font(.headline)
                    SettingsDescription("Try an action name, command or shortcut notation such as alt-h.")
                    Button("Clear search") { query = "" }
                }
            }
        }
        .formStyle(.grouped)

    }
    private func modifierSidePicker(_ title: String, key: String, selection: Binding<String>) -> some View {
        SettingsPicker(title, id: "modifiers.\(key)", selection: selection,
            help: "Applies to shortcut combinations using this modifier. Both preserves the default behavior.") {
            Text("Both").tag("both")
            Text("Left").tag("left")
            Text("Right").tag("right")
        } onChange: {
            persistSettingsConfig(section: "modifiers", key: key,
                renderedValue: "'\(selection.wrappedValue)'", model: model)
        }
    }



}

struct ShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let section: ShortcutSettingsModel.Section

    var body: some View {
        Section {
            if section.id == "managed-focus" {
                ManagedDirectionalShortcutsView(model: model)
            } else if section.id == "managed-move" {
                EmptyView()
            } else if section.id == "workspaces" {
                WorkspaceShortcutSectionView(model: model)
            } else {
                ForEach(section.actions) { action in
                    ShortcutRow(model: model, action: action)
                }
            }
        } header: {
            if section.id != "managed-focus" {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                    if let summary = section.summary {
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}


struct ShortcutRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let action: ShortcutSettingsModel.Action

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body.weight(.medium))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderView(
                title: action.title + " shortcut",
                shortcut: .init(get: { model.shortcutValue(for: action.id) },
                                set: { model.setShortcutValue($0, for: action.id) }),
                onChange: { _ in }
            )
            .frame(width: 160, height: 28)
        }
        .padding(.vertical, 6)
    }
}
