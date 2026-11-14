import SwiftUI

struct SettingsColumnIllustration: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.4)))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.27))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.4))
                    .frame(width: max(8, geometry.size.width * min(max(fraction, 0.1), 1) - 4))
                    .padding(.leading, 2)
            }
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }
}

struct SettingsColumnWidthPicker: View {
    @Binding var value: Int
    let save: () -> Void
    private let choices: [(Int, String)] = [(33, "Compact"), (50, "Balanced"),
                                           (67, "Wide"), (100, "Full")]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default width for new columns")
            HStack(spacing: 8) {
                ForEach(choices, id: \.0) { percent, name in
                    let selected = abs(value - percent) <= 1
                    Button {
                        guard value != percent else { return }
                        value = percent
                        ShortcutSettingsModel.shared.activeSettingTitle = "Default column width"
                        save()
                    } label: {
                        VStack(spacing: 6) {
                            SettingsColumnIllustration(fraction: Double(percent) / 100)
                            Text("\(percent)%").font(.body.monospacedDigit().weight(.semibold))
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name), \(percent) percent")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            SettingsDescription("New columns use this proportion of the available display. Existing resized columns keep their own widths. Current: \(value)%.")
        }
        .modifier(SettingsFieldFeedback(id: "scrolling.column-width", title: "Default column width"))
    }
}

enum SettingsColumnPresetChoices {
    static let common: [Double] = [0.25, 0.3333, 0.5, 0.6667, 0.75, 1.0]
    static func contains(_ value: Double, in selected: [Double]) -> Bool {
        selected.contains { abs($0 - value) < 0.001 }
    }
    static func toggled(_ value: Double, in current: [Double]) -> [Double] {
        let updated = contains(value, in: current)
            ? current.filter { abs($0 - value) >= 0.001 }
            : current + [value]
        return updated.isEmpty ? current : updated.sorted()
    }
}

struct SettingsColumnPresetPicker: View {
    @Binding var values: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Column size shortcuts")
            SettingsDescription("Choose the widths the next/previous size shortcuts cycle through.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(SettingsColumnPresetChoices.common, id: \.self) { option in
                    let active = SettingsColumnPresetChoices.contains(option, in: values)
                    Button {
                        let next = SettingsColumnPresetChoices.toggled(option, in: values)
                        guard next != values else { return }
                        ShortcutSettingsModel.shared.activeSettingTitle = "Column size shortcuts"
                        values = next
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(active ? Color.accentColor : Color.secondary)
                            Text("\(Int((option * 100).rounded()))%").monospacedDigit()
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(active ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Int((option * 100).rounded())) percent")
                    .accessibilityValue(active ? "Enabled" : "Disabled")
                }
            }
            let custom = values.filter { value in
                !SettingsColumnPresetChoices.common.contains { abs($0 - value) < 0.001 }
            }
            if !custom.isEmpty {
                SettingsDescription("Custom widths: " + custom.map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: ", ") + ". Edit them under Custom column sizes.")
            }
        }
        .modifier(SettingsFieldFeedback(id: "scrolling.width-presets", title: "Column size shortcuts"))
    }
}
