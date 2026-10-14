// CrannyCalendar/UI/Settings/SettingRow.swift — the Settings conventions for a module-owned row (DESIGN.md §11.3),
// from CrannyCore (`crannySettingRow`): module panes are opaque views to CrannySettingsUI.
import CrannyCore
import Foundation
import SwiftUI

extension View {
    /// Marks the row of `key`: Core's row conventions (accent dot when changed, "Reset to Default" in the context
    /// menu and as a VoiceOver action).
    func settingRow<Value>(_ settings: SettingsStore, _ key: SettingKey<Value>) -> some View {
        crannySettingRow(settings, key)
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
