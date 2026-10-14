// CrannyCalendar/UI/Settings/CalendarSettingsPane.swift — Settings ▸ Calendar (DESIGN.md §11.1): calendars (a
// checkbox list with colours, grouped by account), the days the widget can show, today's past events, all-day
// events, meeting-link services and where Join opens. An ordinary window: system controls and colours.
import CrannyCore
import Foundation
import SwiftUI

struct CalendarSettingsPane: View {
    let model: CalendarModel
    private var settings: SettingsStore { model.settings }

    var body: some View {
        Form {
            Section {
                CalendarList(model: model)
            } header: {
                Text("Calendars", bundle: .module, comment: "Settings ▸ Calendar: section title")
            } footer: {
                if model.store.accessStatus == .granted {
                    Footnote(String(localized: "Hidden calendars never appear in the widget or as live activities.", bundle: .module,
                                    comment: "Settings ▸ Calendar: footnote under the calendar list"))
                }
            }

            Section {
                DayRangeRows(settings: settings)
                toggle(CalendarSettings.showsPastEventsToday, String(localized: "Show today's past events", bundle: .module, comment: "Calendar options: keep ended events in today's list"))
                toggle(CalendarSettings.includesAllDay, String(localized: "Show all-day events", bundle: .module, comment: "Settings ▸ Calendar: toggle"))
            } header: {
                Text("Events", bundle: .module, comment: "Settings ▸ Calendar: section title")
            }

            Section {
                let openIn = Text("Open meetings in", bundle: .module, comment: "Settings ▸ Calendar: where Join opens a meeting")
                LabeledContent {
                    Picker(selection: settings.binding(CalendarSettings.joinsInApp)) {
                        Text("App", bundle: .module, comment: "Settings ▸ Calendar ▸ Open meetings in: the service's own app").tag(true)
                        Text("Browser", bundle: .module, comment: "Settings ▸ Calendar ▸ Open meetings in: the web browser").tag(false)
                    } label: {
                        openIn
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    openIn
                }
                .settingRow(settings, CalendarSettings.joinsInApp)
                ServiceGrid(settings: settings)
            } header: {
                Text("Meeting links", bundle: .module, comment: "Settings ▸ Calendar: section title (services that get a Join button)")
            } footer: {
                Footnote(String(localized: "Join appears when an event's URL, location or notes link to one of these services. The app is used only when it is installed.",
                                bundle: .module, comment: "Settings ▸ Calendar: footnote under the meeting services"))
            }
        }
        .formStyle(.grouped)
        .onAppear { if !model.isSample { model.store.refreshAccess() } }       // never prompts
    }

    private func toggle(_ key: SettingKey<Bool>, _ label: String) -> some View {
        Toggle(isOn: settings.binding(key)) { Text(label) }
            .toggleStyle(.switch)
            .controlSize(.small)
            .settingRow(settings, key)
    }

    /// The pane's search terms (Settings search matches a module pane only through these, §3.7): only rows this
    /// pane shows. The meeting lead time lives under Meeting soon in Settings ▸ Live Activities.
    static var keywords: [String] {
        [String(localized: "Calendars", bundle: .module, comment: "Settings ▸ Calendar: section title"),
         String(localized: "Days before today", bundle: .module, comment: "Calendar settings: how many past days the widget can show"),
         String(localized: "Days after today", bundle: .module, comment: "Calendar settings: how many future days the widget can show"),
         String(localized: "Show today's past events", bundle: .module, comment: "Calendar options: keep ended events in today's list"),
         String(localized: "Show all-day events", bundle: .module, comment: "Settings ▸ Calendar: toggle"),
         String(localized: "Meeting links", bundle: .module, comment: "Settings ▸ Calendar: section title (services that get a Join button)"),
         String(localized: "Open meetings in", bundle: .module, comment: "Settings ▸ Calendar: where Join opens a meeting"),
         String(localized: "Join", bundle: .module, comment: "Calendar: Join button title (opens the meeting link)"),
         String(localized: "Birthdays", bundle: .module, comment: "Settings ▸ Calendar: search keyword for the birthdays calendar"),
         String(localized: "Events", bundle: .module, comment: "Settings ▸ Calendar: section title")]
            + MeetingService.allCases.map(\.displayName)
    }
}

/// The calendars, grouped by account, each a checkbox with its colour. Without access: why, and the way to it.
private struct CalendarList: View {
    let model: CalendarModel

    var body: some View {
        let settings = model.settings
        if model.store.accessStatus == .granted {
            let groups = Dictionary(grouping: model.store.calendars, by: \.sourceTitle)
            let sources = groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if sources.isEmpty {
                Text("No calendars yet", bundle: .module, comment: "Settings ▸ Calendar: the account has no calendars (or they are still loading)")
                    .foregroundStyle(.secondary)
            }
            ForEach(sources, id: \.self) { source in
                VStack(alignment: .leading, spacing: 6) {
                    if !source.isEmpty {
                        Text(verbatim: source).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(groups[source] ?? []) { info in
                        Toggle(isOn: visibility(info, settings)) {
                            HStack(spacing: 6) {
                                Circle().fill(info.color.color).frame(width: 9, height: 9).accessibilityHidden(true)
                                Text(verbatim: info.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .settingRow(settings, CalendarSettings.hiddenCalendarIDs)
        } else {
            AccessRow(model: model)
        }
    }

    /// Ordinary calendars: `hiddenCalendarIDs`. The Birthdays calendar: `includesBirthdays` (one switch per idea).
    private func visibility(_ info: CalendarInfo, _ settings: SettingsStore) -> Binding<Bool> {
        if info.isBirthdays { return settings.binding(CalendarSettings.includesBirthdays) }
        return Binding {
            !settings[CalendarSettings.hiddenCalendarIDs].contains(info.id)
        } set: { visible in
            var hidden = settings[CalendarSettings.hiddenCalendarIDs].filter { $0 != info.id }
            if !visible { hidden.append(info.id) }
            settings[CalendarSettings.hiddenCalendarIDs] = hidden.sorted()
        }
    }
}

/// "Cranny can't see your calendars yet" + Permissions… / Open System Settings. Never the system prompt: Cranny
/// asks for Calendar access only from the widget's "Show your events" or onboarding (ARCHITECTURE.md §7.4,
/// DESIGN.md §6.8); Settings ▸ Permissions is where the Settings window handles every permission.
private struct AccessRow: View {
    let model: CalendarModel

    var body: some View {
        let status = model.store.accessStatus
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(status == .denied ? String(localized: "Calendar access is off.", bundle: .module, comment: "Calendar widget: access was denied in System Settings")
                                       : String(localized: "Cranny can't see your calendars yet.", bundle: .module, comment: "Settings ▸ Calendar: access not granted yet"))
                Text("Show your events in Cranny. Cranny never edits or uploads them.", bundle: .module,
                     comment: "Permission reason: Calendar (Settings ▸ Calendar, Permissions pane, onboarding)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .denied {
                Button { model.store.openPrivacySettings() } label: {
                    Text("Open System Settings", bundle: .module, comment: "Calendar widget: button that opens Privacy & Security ▸ Calendars")
                }
            } else if status == .notDetermined {
                Button { model.openPermissionsSettings() } label: {
                    Text("Permissions…", bundle: .module, comment: "Settings ▸ Calendar: opens Settings ▸ Permissions (calendar access is not granted yet)")
                }
                .disabled(model.isSample)
            }
        }
    }
}

/// One checkbox per meeting service (product names are not translated).
private struct ServiceGrid: View {
    let settings: SettingsStore

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(MeetingService.allCases, id: \.self) { service in
                Toggle(isOn: binding(service)) { Text(verbatim: service.displayName) }
                    .toggleStyle(.checkbox)
            }
        }
        .settingRow(settings, CalendarSettings.joinProviders)
    }

    private func binding(_ service: MeetingService) -> Binding<Bool> {
        Binding {
            settings[CalendarSettings.joinProviders].contains(service)
        } set: { on in
            let current = Set(settings[CalendarSettings.joinProviders])
            let next = on ? current.union([service]) : current.subtracting([service])
            settings[CalendarSettings.joinProviders] = MeetingService.allCases.filter(next.contains)   // stable order
        }
    }
}

private struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary) }
}

#Preview("Settings ▸ Calendar") {
    CalendarSettingsPane(model: .sample(services: CrannyServices.preview()))
        .frame(width: 600, height: 640)
}

#Preview("Settings ▸ Calendar · no access") {
    CalendarSettingsPane(model: .sample(services: CrannyServices.preview(), access: .notDetermined))
        .frame(width: 600, height: 420)
}
