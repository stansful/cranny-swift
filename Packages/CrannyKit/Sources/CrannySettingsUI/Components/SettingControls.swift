// CrannySettingsUI/Components/SettingControls.swift — the row kinds of DESIGN.md §11.3: switches (`.switch`,
// `.small`), segmented pickers for up to four short options and menus otherwise, sliders that always show
// their value with units and tick marks at the steps. Each applies the row conventions of `SettingRow`.
import CrannyCore
import Foundation
import SwiftUI

/// One option of a picker row.
struct Choice<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// How a picker row draws its options.
enum ChoiceStyle {
    /// Segmented for up to four options, a menu otherwise (§11.3).
    case automatic
    case segmented
    case menu
}

/// A switch row backed by a Bool key.
struct ToggleRow: View {
    let info: SettingsRowInfo
    let settings: SettingsStore
    let key: SettingKey<Bool>
    var footnote: String?

    var body: some View {
        Toggle(isOn: settings.binding(key)) {
            RowLabel(title: info.title, footnote: footnote, isChanged: !settings.isDefault(key))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .settingRow(info, settings: settings, key: key)
    }
}

/// A picker row. `init(_:settings:key:…)` binds a settings key; the memberwise form takes any binding.
struct ChoiceRow<Value: Hashable>: View {
    let info: SettingsRowInfo
    let selection: Binding<Value>
    let choices: [Choice<Value>]
    var footnote: String?
    var style: ChoiceStyle = .automatic
    let isDefault: Bool
    let reset: @MainActor () -> Void

    var body: some View {
        let picker = Picker(selection: selection) {
            ForEach(choices) { choice in
                Text(verbatim: choice.label).tag(choice.value)
            }
        } label: {
            Text(verbatim: info.title)
        }
        .labelsHidden()
        LabeledContent {
            if usesSegments {
                // Segments when they fit (Russian runs 15–35 % longer), a menu otherwise.
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
            } else {
                picker.pickerStyle(.menu).fixedSize()
            }
        } label: {
            RowLabel(title: info.title, footnote: footnote, isChanged: !isDefault)
        }
        .settingRow(info, isDefault: isDefault, reset: reset)
    }

    private var usesSegments: Bool {
        switch style {
        case .automatic: choices.count <= 4
        case .segmented: true
        case .menu: false
        }
    }
}

extension ChoiceRow where Value: Codable & Sendable {
    init(_ info: SettingsRowInfo, settings: SettingsStore, key: SettingKey<Value>, choices: [Choice<Value>],
         footnote: String? = nil, style: ChoiceStyle = .automatic) {
        self.init(info: info, selection: settings.binding(key), choices: choices, footnote: footnote, style: style,
                  isDefault: settings.isDefault(key), reset: { settings.reset(key) })
    }
}

/// A slider row: label on the leading side, slider with tick marks at its steps and the formatted value.
struct SliderRow: View {
    let info: SettingsRowInfo
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    /// "120 ms", "+2 pt" — the value with its unit, always shown (§11.3).
    let format: (Double) -> String
    var footnote: String?
    let isDefault: Bool
    let reset: @MainActor () -> Void
    var onEditingChanged: @MainActor (Bool) -> Void = { _ in }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step) {
                    Text(verbatim: info.title)
                } onEditingChanged: { editing in
                    onEditingChanged(editing)
                }
                .labelsHidden()
                .frame(minWidth: 140, idealWidth: 200, maxWidth: 220)
                .accessibilityValue(Text(verbatim: format(value.wrappedValue)))
                Text(verbatim: format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        } label: {
            RowLabel(title: info.title, footnote: footnote, isChanged: !isDefault)
        }
        .settingRow(info, isDefault: isDefault, reset: reset)
    }
}

extension SliderRow {
    /// A slider bound to a Double key.
    init(_ info: SettingsRowInfo, settings: SettingsStore, key: SettingKey<Double>, range: ClosedRange<Double>, step: Double,
         footnote: String? = nil, format: @escaping (Double) -> String) {
        self.init(info: info, value: settings.binding(key), range: range, step: step, format: format, footnote: footnote,
                  isDefault: settings.isDefault(key), reset: { settings.reset(key) })
    }
}

/// A section header in the system style, from an already-localized string.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(verbatim: text) }
}

#Preview("Controls") {
    let settings = ModuleRegistry(services: .preview()).services.settings
    Form {
        ToggleRow(info: SettingsRowInfo(.general, "closeOnLeave", title: "Close when the pointer leaves"),
                  settings: settings, key: CoreSettings.closeOnLeave, footnote: "After a 300 ms grace period.")
        ChoiceRow(SettingsRowInfo(.appearance, "motion", title: "Motion"), settings: settings, key: CoreSettings.motion,
                  choices: MotionPersonality.allCases.map { Choice(value: $0, label: $0.rawValue.capitalized) })
        SliderRow(SettingsRowInfo(.appearance, "panelPadding", title: "Panel padding"), settings: settings,
                  key: CoreSettings.panelPaddingTune, range: -4...4, step: 1) { SettingsFormat.points($0) }
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 260)
}
