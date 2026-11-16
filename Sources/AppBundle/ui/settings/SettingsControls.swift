import SwiftUI

struct SettingsScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsSearchTarget) private var searchTarget
    var body: some View {
        ScrollViewReader { proxy in
            Form { content }.formStyle(.grouped)
                .onPreferenceChange(SettingsSearchReadyKey.self) { ready in
                    guard let ready, ready == searchTarget else { return }
                    proxy.scrollTo(ready.id, anchor: .center)
                }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        Section { content } header: { Text(title).accessibilityAddTraits(.isHeader) }
    }
}

struct SettingsToggle: View {
    let title: String
    let id: String
    @Binding var isOn: Bool
    var help: String? = nil
    let save: () -> Void

    init(_ title: String, id: String? = nil, isOn: Binding<Bool>, help: String? = nil, save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _isOn = isOn
        self.help = help
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(get: { isOn }, set: { value in
                guard value != isOn else { return }
                isOn = value
                ShortcutSettingsModel.shared.activeSettingTitle = title
                save()
            }))
            .frame(minHeight: 28)
            .accessibilityIdentifier(id)
            .accessibilityLabel(title)
            .accessibilityHint(help ?? "")
            if let help { SettingsDescription(help) }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }
}

struct SettingsDescription: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsStepper: View {
    let title: String
    let id: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let help: String
    let unit: String
    let save: () -> Void
    @FocusState private var focused: Bool
    @State private var submitted: Int?

    init(_ title: String, id: String? = nil, value: Binding<Int>, range: ClosedRange<Int>, help: String, unit: String = "pt", save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _value = value
        self.range = range
        self.help = help
        self.unit = unit
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(); editor }
                VStack(alignment: .leading) { Text(title); editor }
            }
            SettingsDescription(help)
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { submitted = value }
        .onDisappear { commit() }
        .onChange(of: focused) { if !$0 { commit() } }
        .onChange(of: value) { newValue in
            if !focused { submitted = newValue }
        }
    }

    private var editor: some View {
        HStack {
            TextField(title, value: $value, format: .number)
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80, height: 28)
                .focused($focused).onSubmit(commit)
                .accessibilityLabel(title).accessibilityValue("\(value) \(unit)")
                .accessibilityIdentifier(id + ".value")
            Text(unit).foregroundStyle(.secondary).accessibilityHidden(true)
            Stepper(title, value: Binding(get: { value }, set: { newValue in
                value = newValue
                commit(force: true)
            }), in: range).labelsHidden()
                .accessibilityLabel(title).accessibilityValue("\(value) \(unit)")
        }
    }

    private func commit() { commit(force: false) }
    private func commit(force: Bool) {
        guard force || submitted != value else { return }
        value = min(max(value, range.lowerBound), range.upperBound)
        submitted = value
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save()
    }
}

struct SettingsTextField: View {
    @FocusState private var isFocused: Bool
    @State private var committedText: String?
    @State private var wasEdited = false
    let title: String
    let id: String
    @Binding var text: String
    let help: String
    let validate: (String) -> String?
    let save: () -> Void

    init(_ title: String, id: String? = nil, text: Binding<String>, help: String,
         validate: @escaping (String) -> String? = { _ in nil }, save: @escaping () -> Void) {
        self.title = title
        self.id = id ?? title
        _text = text
        self.help = help
        self.validate = validate
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: Binding(get: { text }, set: { value in
                text = value
                wasEdited = true
            }))
                .focused($isFocused)
                .onAppear { committedText = text }
                .onSubmit(commit)
                .onChange(of: isFocused) { focused in if !focused { commit() } }
                .onDisappear { commit() }
                .settingsAutosave(value: text, enabled: wasEdited, commit: commit)
                .help(help)
                .accessibilityIdentifier(id)
                .accessibilityLabel(title)
            SettingsDescription(help)
            if let error = validate(text) {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }

    private func commit() {
        guard wasEdited, let committedText, committedText != text, validate(text) == nil else { return }
        self.committedText = text
        wasEdited = false
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save()
    }
}

func settingsHexColorError(_ text: String) -> String? {
    guard normalizedWindowBorderColor(text) != nil else {
        return "Use # followed by six or eight hexadecimal digits, for example #E1E3E4."
    }
    return nil
}

struct SettingsMultilineField: View {
    @State private var savedText: String?
    @State private var isSaving = false
    @State private var attemptedText: String?
    @State private var wasEdited = false
    let title: String
    let id: String
    @Binding var text: String
    let help: String
    let savedValue: String
    let save: (@escaping () -> Void) -> Void

    init(_ title: String, id: String? = nil, text: Binding<String>, help: String, savedValue: String, save: @escaping (@escaping () -> Void) -> Void) {
        self.title = title
        self.id = id ?? title
        _text = text
        self.help = help
        self.save = save
        self.savedValue = savedValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            SettingsDescription(help)
            TextEditor(text: Binding(get: { text }, set: { value in
                text = value
                wasEdited = true
            }))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .accessibilityLabel(title).accessibilityHint(help)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            if isSaving { Text("Saving…").font(.callout).foregroundStyle(.secondary) }
        }
        .padding(12)
        .modifier(SettingsFieldFeedback(id: id, title: title))
        .onAppear { savedText = savedValue }
        .onChange(of: savedValue) { savedText = $0; isSaving = false }
        .settingsAutosave(value: text, enabled: wasEdited && !isSaving) { commit() }
        .onReceive(ShortcutSettingsModel.shared.$failedSettingID) { failedID in
            if failedID == id { isSaving = false }
        }
    }

    private func commit() {
        guard wasEdited, !isSaving, savedText != text, attemptedText != text else { return }
        let submitted = text
        attemptedText = submitted
        isSaving = true
        ShortcutSettingsModel.shared.activeSettingTitle = title
        save {
            savedText = submitted
            if text == submitted { wasEdited = false }
            isSaving = false
        }
    }

}

struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String
    let id: String
    @Binding var selection: Selection
    let help: String
    @ViewBuilder let content: Content
    let onChange: () -> Void
    init(_ title: String, id: String? = nil, selection: Binding<Selection>, help: String, @ViewBuilder content: () -> Content, onChange: @escaping () -> Void) {
        self.title = title; self.id = id ?? title; _selection = selection
        self.help = help; self.content = content(); self.onChange = onChange
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: Binding(get: { selection }, set: { value in
                guard value != selection else { return }
                selection = value
                ShortcutSettingsModel.shared.activeSettingTitle = title
                onChange()
            }), content: { content })
                .accessibilityIdentifier(id).accessibilityHint(help)
            if !help.isEmpty { SettingsDescription(help) }
        }
        .modifier(SettingsFieldFeedback(id: id, title: title))
    }
}

struct SettingsFieldFeedback: ViewModifier {
    let id: String
    let title: String
    @ObservedObject private var model = ShortcutSettingsModel.shared
    @Environment(\.settingsSearchTarget) private var searchTarget

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if model.failedSettingID == id, let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).textSelection(.enabled)
                    .accessibilityLabel("Could not save \(title). \(error)")
            }
        }
        .id(id)
        .background(Color.clear.preference(key: SettingsSearchReadyKey.self,
            value: searchTarget?.id == id ? searchTarget : nil))
    }
}

func normalizedWorkspaceSidebarColorHex(_ raw: String) -> String? {
    guard raw.hasPrefix("#"), raw.count == 7, UInt32(raw.dropFirst(), radix: 16) != nil else { return nil }
    return raw.uppercased()
}

struct SettingsDisplayError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
