// CrannyCalendar/UI/Settings/MeetingActivityOptions.swift — the rows under the meeting activities in Settings ▸
// Live Activities (DESIGN.md §11.1: "meeting lead time (1–30 min, default 5) and show while in an event (elapsed /
// remaining) under the meeting rows"). The shell-owned pane cannot import module settings, so the module
// supplies them (`registry.add(activity:…, options:)`).
import CrannyCore
import Foundation
import SwiftUI

/// Under "Meeting soon": the lead time.
struct MeetingSoonOptions: View {
    let settings: SettingsStore

    var body: some View {
        let minutes = settings[CalendarSettings.leadMinutes]
        let label = Text("Lead time", bundle: .module, comment: "Live Activities ▸ Meeting soon: how long before a meeting it appears")
        LabeledContent {
            HStack(spacing: 6) {
                Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(value: settings.binding(CalendarSettings.leadMinutes), in: CalendarSettings.leadRange) { label }
                    .labelsHidden()
            }
        } label: {
            label
        }
        .settingRow(settings, CalendarSettings.leadMinutes)
        .help(String(localized: "Meeting soon appears this long before an event, and again one minute before.", bundle: .module,
                     comment: "Live Activities ▸ Meeting soon: tooltip of the lead time row"))
    }
}

/// Under "Meeting in progress": time left or time elapsed.
struct MeetingNowOptions: View {
    let settings: SettingsStore

    var body: some View {
        Picker(selection: settings.binding(CalendarSettings.inEventDisplay)) {
            Text("Time left", bundle: .module, comment: "Live Activities ▸ Meeting in progress ▸ Show: remaining time").tag(InEventDisplay.remaining)
            Text("Time elapsed", bundle: .module, comment: "Live Activities ▸ Meeting in progress ▸ Show: elapsed time").tag(InEventDisplay.elapsed)
        } label: {
            Text("Show", bundle: .module, comment: "Live Activities ▸ Meeting in progress: what the activity counts")
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .settingRow(settings, CalendarSettings.inEventDisplay)
    }
}

#Preview("Live Activities rows") {
    let settings = CrannyServices.preview().settings
    return Form {
        Section { MeetingSoonOptions(settings: settings) } header: { Text(verbatim: "Meeting soon") }
        Section { MeetingNowOptions(settings: settings) } header: { Text(verbatim: "Meeting in progress") }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 260)
}
