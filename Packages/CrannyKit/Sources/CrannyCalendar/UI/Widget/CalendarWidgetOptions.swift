// CrannyCalendar/UI/Widget/CalendarWidgetOptions.swift — the widget's options popover (Settings ▸ Layout &
// Widgets and the card's ⋯ menu, DESIGN.md §11.1: days behind / ahead and past events). System controls: this
// renders in an ordinary popover, not on the notch.
import CrannyCore
import Foundation
import SwiftUI

struct CalendarWidgetOptions: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            DayRangeRows(settings: settings)
            Toggle(isOn: settings.binding(CalendarSettings.showsPastEventsToday)) {
                Text("Show today’s past events", bundle: .module, comment: "Calendar options: keep ended events in today's list")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .formStyle(.grouped)
        .frame(minWidth: 300)
    }
}

/// "Days before today" / "Days after today" steppers (0–7), shared with Settings ▸ Calendar.
struct DayRangeRows: View {
    let settings: SettingsStore

    var body: some View {
        stepper(CalendarSettings.daysBehind,
                label: String(localized: "Days before today", bundle: .module, comment: "Calendar settings: how many past days the widget can show"))
        stepper(CalendarSettings.daysAhead,
                label: String(localized: "Days after today", bundle: .module, comment: "Calendar settings: how many future days the widget can show"))
    }

    private func stepper(_ key: SettingKey<Int>, label: String) -> some View {
        let value = settings[key]
        return LabeledContent {
            HStack(spacing: 6) {
                Text("\(value) days", bundle: .module, comment: "Calendar settings: a number of days (plural)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(value: settings.binding(key), in: CalendarSettings.dayRange) { Text(label) }
                    .labelsHidden()
            }
        } label: {
            Text(label)
        }
        .settingRow(settings, key)
    }
}

#Preview("Widget options") {
    CalendarWidgetOptions(settings: CrannyServices.preview().settings)
        .frame(width: 360)
}
