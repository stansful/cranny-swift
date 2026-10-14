// CrannyCalendar/UI/Settings/SettingRow.swift — the Settings conventions for a module-owned row (DESIGN.md §11.3):
// a 6-pt accent dot before a changed value and "Reset to Default" in the row's context menu. Module panes are
// opaque views to CrannySettingsUI, so the module applies them itself.
import CrannyCore
import Foundation
import SwiftUI

extension View {
    /// Marks the row of `key`: accent dot when not default, context menu "Reset to Default".
    func settingRow<Value>(_ settings: SettingsStore, _ key: SettingKey<Value>) -> some View {
        modifier(SettingRowModifier(settings: settings, key: key))
    }
}

private struct SettingRowModifier<Value: Codable & Sendable & Equatable>: ViewModifier {
    let settings: SettingsStore
    let key: SettingKey<Value>

    func body(content: Content) -> some View {
        let changed = !settings.isDefault(key)
        content
            .overlay(alignment: .leading) {
                if changed {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -9)                    // inside the grouped row's 10-pt inset
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                Button {
                    settings.reset(key)
                } label: {
                    Text("Reset to Default", bundle: .module, comment: "Settings: context menu item that restores a row's default value")
                }
                .disabled(!changed)
            }
    }
}

#Preview("Setting row") {
    let settings = CrannyServices.preview().settings
    settings[CalendarSettings.leadMinutes] = 10
    return Form {
        Text(verbatim: "Changed row").settingRow(settings, CalendarSettings.leadMinutes)
        Text(verbatim: "Default row").settingRow(settings, CalendarSettings.daysAhead)
    }
    .formStyle(.grouped)
    .frame(width: 360, height: 160)
}
