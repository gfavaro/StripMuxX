import AppKit
import Common
import SwiftUI

struct SettingsDisplayRow: Identifiable, Equatable {
    let id: String
    let name: String
    let resolution: String
    let isMain: Bool
    let uuid: String?
    let hardware: String?
    let workspaces: [String]
    let activeWorkspace: String?
}

@MainActor
func workspaceDisplayName(_ workspaceName: String) -> String {
    if let ws = userWorkspace(named: workspaceName) ?? Workspace.existing(byName: workspaceName) {
        return userFacingWorkspaceName(ws)
    }
    return workspaceName
}

@MainActor
final class SettingsDisplaysModel: ObservableObject {
    @Published private(set) var rows: [SettingsDisplayRow] = []
    @Published var assignment = SettingsAssignmentDraft()

    func refresh() {
        let next = sortedMonitors.map { monitor in
            let active = nativeActiveDesktop(on: monitor)
            return SettingsDisplayRow(
                id: monitor.displayUUID.map { "uuid:\($0)" } ?? "index:\(monitor.monitorAppKitNsScreenScreensId)",
                name: monitor.name, resolution: "\(Int(monitor.width)) × \(Int(monitor.height)) pt",
                isMain: monitor.isMain, uuid: monitor.displayUUID,
                hardware: monitor.hardwareIdentity?.selector,
                workspaces: active.map { [userFacingWorkspaceName($0)] } ?? [],
                activeWorkspace: active.map(userFacingWorkspaceName),
            )
        }
        setIfChanged(\.rows, next)
    }

    func bringHere(workspace: String, selector: String, expectedVisibleWorkspace: String? = nil) async throws {
        guard let description = parseMonitorDescription(selector).getOrNil(),
              let currentMonitor = description.resolveMonitor(sortedMonitors: sortedMonitors),
              let command = parseCommand(["move-workspace-to-monitor", selector]).cmdOrNil
        else { throw SettingsDisplayError("The workspace or display is no longer available.") }
        if let expectedVisibleWorkspace,
           nativeActiveDesktop(on: currentMonitor).map(userFacingWorkspaceName) != expectedVisibleWorkspace {
            throw SettingsDisplayError("The destination workspace changed. Review the move and try again.")
        }
        let result = try await command.run(CmdEnv(workspaceName: workspace), .emptyStdin)
        guard result.exitCode == 0 else { throw SettingsDisplayError(result.stderr.joined(separator: "\n")) }
    }
}

struct SettingsDisplaysView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject var displays: SettingsDisplaysModel
    @State private var attemptedAssignment: SettingsAssignmentDraft?
    @State private var isSavingAssignment = false
    @State private var error: String?
    var onGeneral: () -> Void

    var body: some View {
        SettingsScrollView {
            SettingsSection("Connected displays") {
                if displays.rows.isEmpty { SettingsDescription("No connected displays are available. Saved assignments remain unchanged.") }
                ForEach(displays.rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.name).font(.headline)
                            if row.isMain { Text("Main").foregroundStyle(.secondary) }
                            Spacer()
                            Text(row.resolution).foregroundStyle(.secondary)
                        }
                        Text("Desktop: " + (row.workspaces.isEmpty ? "None" : row.workspaces.map { workspaceDisplayName($0) }.joined(separator: ", ")))
                        if let uuid = row.uuid {
                            HStack {
                                Text(uuid).font(.caption.monospaced()).textSelection(.enabled)
                                Button("Copy UUID") { copy("uuid:" + uuid) }
                            }
                        }
                        if let hardware = row.hardware {
                            Button("Copy hardware selector") { copy(hardware) }
                        }
                    }.padding(.vertical, 6)
                }
            }
            SettingsSection("Configured assignments") {
                if config.workspaceToMonitorForceAssignment.isEmpty {
                    SettingsDescription("No saved display assignments. Added desktops go to the main display.")
                }
                ForEach(config.workspaceToMonitorForceAssignment.keys.sorted(), id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workspaceDisplayName(name))
                            Text(assignmentSummary(name)).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).help(assignmentSummary(name))
                        }
                        Spacer()
                        Button("Edit") { editAssignment(name) }
                        Button("Remove") { removeAssignment(name) }
                    }
                }
                assignmentEditor
                SettingsDescription("Advanced: these assignments affect only where StripMuxX creates new native desktops. They do not move or pin existing macOS Spaces.")
                Button("Startup options…", action: onGeneral)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onAppear { displays.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).receive(on: RunLoop.main)) { _ in displays.refresh() }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var assignmentEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if displays.assignment.isEditing {
                LabeledContent("Workspace", value: workspaceDisplayName(displays.assignment.workspace))
            } else {
                Picker("Workspace", selection: $displays.assignment.workspace) {
                    Text("Choose workspace").tag("")
                    ForEach((1...9).map(String.init), id: \.self) { num in Text(num).tag(num) }
                    if !displays.assignment.workspace.isEmpty && !(1...9).map(String.init).contains(displays.assignment.workspace) {
                        Text(displays.assignment.workspace).tag(displays.assignment.workspace)
                    }
                }
            }
            if !displays.assignment.advanced {
                Picker("Display", selection: $displays.assignment.selector) {
                    Text("Choose display").tag("")
                    ForEach(displays.rows.filter { $0.uuid != nil }) { row in Text(row.name).tag(row.id) }
                    if !displays.assignment.selector.isEmpty && !displays.rows.contains(where: { $0.id == displays.assignment.selector }) {
                        Text("Current advanced selection — " + displays.assignment.selector).tag(displays.assignment.selector)
                    }
                }
            }
            DisclosureGroup("Advanced", isExpanded: $displays.assignment.advanced) {
                if !displays.assignment.isEditing {
                    SettingsEditorField("Desktop number", prompt: "Number for a native desktop to be created", text: $displays.assignment.workspace)
                }
                SettingsEditorField("Display selector", prompt: "uuid:…, hardware:… or an array", text: $displays.assignment.selector)
                SettingsDescription("Use UUIDs for exact displays. Arrays retain ordered alternatives. Unavailable assignments are kept until you explicitly change them.")
            }
            HStack {
                if !displays.assignment.isEditing {
                    Button("Add assignment") { saveAssignment() }
                        .disabled(!displays.assignment.isDirty || displays.assignment.workspace.isEmpty || displays.assignment.selector.isEmpty)
                }
                if isSavingAssignment { Text("Saving…").foregroundStyle(.secondary) }
                if displays.assignment.isDirty || displays.assignment.isEditing {
                    Button(displays.assignment.isDirty ? "Discard changes" : "Done") { displays.assignment = SettingsAssignmentDraft() }
                }
            }
        }
        .disabled(isSavingAssignment || model.savingSettingIDs.contains("workspace-to-monitor-force-assignment"))
        .settingsAutosave(value: displays.assignment, enabled: displays.assignment.isEditing && displays.assignment.isDirty && !isSavingAssignment && displays.assignment != attemptedAssignment) {
            guard displays.assignment.isDirty, displays.assignment != attemptedAssignment else { return }
            do { _ = try displays.assignment.renderedSelectors() }
            catch { self.error = error.localizedDescription; return }
            saveAssignment()
        }
    }

    private func assignmentSummary(_ name: String) -> String {
        config.workspaceToMonitorForceAssignment[name, default: []].map { selector in
            if let row = displays.rows.first(where: { $0.id == selector.selector }) { return row.name }
            if selector.resolveMonitor(sortedMonitors: sortedMonitors) != nil { return selector.selector }
            return selector.selector + " (unavailable)"
        }.joined(separator: " → ")
    }

    private func editAssignment(_ name: String) {
        guard !displays.assignment.isDirty else { error = "Finish or discard the current assignment first."; return }
        displays.assignment = .editing(workspace: name, selectors: config.workspaceToMonitorForceAssignment[name, default: []].map(\.selector), connectedSelectors: Set(displays.rows.filter { $0.uuid != nil }.map(\.id)))
        error = nil
    }

    private func saveAssignment() {
        guard !isSavingAssignment else { return }
        let submitted = displays.assignment
        attemptedAssignment = submitted
        isSavingAssignment = true
        model.activeSettingTitle = "Display assignment"
        persistSettingsDocumentEdit(model: model, settingIDs: ["workspace-to-monitor-force-assignment"], onSaved: {
            isSavingAssignment = false
            if displays.assignment == submitted {
                displays.assignment = .editing(workspace: submitted.workspace,
                    selectors: config.workspaceToMonitorForceAssignment[submitted.workspace, default: []].map(\.selector),
                    connectedSelectors: Set(displays.rows.filter { $0.uuid != nil }.map(\.id)))
            }
            error = nil
        }, onFailure: { failure in
            isSavingAssignment = false
            error = failure.localizedDescription
        }) { current in try submitted.applying(to: current) }
    }

    private func removeAssignment(_ name: String) {
        guard !displays.assignment.isDirty else { error = "Finish or discard the current assignment first."; return }
        let original = config.workspaceToMonitorForceAssignment[name]?.map(\.selector)
        model.activeSettingTitle = "Display assignment"
        persistSettingsDocumentEdit(model: model, settingIDs: ["workspace-to-monitor-force-assignment"], onSaved: {
            if displays.assignment.workspace == name { displays.assignment = SettingsAssignmentDraft() }
        }) { current in
            guard parseConfig(current).config.workspaceToMonitorForceAssignment[name]?.map(\.selector) == original else { throw ConfigFileStore.Conflict() }
            return applyingSettingsConfigEdits([.init(section: "workspace-to-monitor-force-assignment", key: settingsQuotedString(name), renderedValue: nil)], to: current)
        }
    }
}
