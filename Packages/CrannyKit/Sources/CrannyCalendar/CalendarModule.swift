// CrannyCalendar/CalendarModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §7.4, §10.3):
// the Calendar widget, the "Meeting soon" (P1 → P2) and "Meeting in progress" (P2) activities with samples and
// Live Activities rows, Settings ▸ Calendar, ⌘K "Join next meeting", and the Calendar permission it may ask for.
// `register(in:)` only builds models: EventKit is touched in `onLaunch`, and only once access is granted.
import CrannyCore
import Foundation
import SwiftUI

/// Calendar: upcoming events, meeting activities and the Calendar widget. Registered by the shell's `CompositionRoot`.
public enum CalendarModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.calendar`).
    public static var id: ModuleID { .calendar }

    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let model = makeModel(services: services)

        registry.add(widget: CalendarWidget(model: model, services: services))
        registry.add(activity: MeetingSoonActivity(model: model), kind: MeetingSoonActivity.kind(),
                     sample: { MeetingSoonActivity(model: .sample(services: services)) },
                     options: { AnyView(MeetingSoonOptions(settings: services.settings)) })
        registry.add(activity: MeetingNowActivity(model: model), kind: MeetingNowActivity.kind(),
                     sample: { MeetingNowActivity(model: .sample(services: services)) },
                     options: { AnyView(MeetingNowOptions(settings: services.settings)) })
        registry.add(settingsPage: SettingsPage(
            id: .calendar,
            title: String(localized: "Calendar", bundle: .module, comment: "Calendar: module name (widget, Settings pane, ⌘K result kind)"),
            symbol: "calendar", tint: .red, group: .features, order: 1,
            keywords: CalendarSettingsPane.keywords, previewState: .open) { AnyView(CalendarSettingsPane(model: model)) })
        registry.add(commands: CalendarCommands(model: model, notch: services.notch))
        registry.declare(.calendar, reason: String(localized: "Show your events in Cranny. Cranny never edits or uploads them.", bundle: .module,
                                                   comment: "Permission reason: Calendar (Settings ▸ Calendar, Permissions pane, onboarding)"))
        registry.onLaunch {
            model.store.start()
            model.scheduler.start(trigger: { model.store.loadCount })
        }
        registry.onTerminate {
            model.scheduler.stop()
            model.store.stop()
        }
    }

    /// The live model: EventKit behind `PermissionsCenter` (or the DEBUG `--qa-calendar` fixture).
    static func makeModel(services: CrannyServices) -> CalendarModel {
        var source: any EventSource = EventKitSource()
        var access: any CalendarAccess = PermissionsCalendarAccess(permissions: services.permissions)
        #if DEBUG
        if let fixture = CalendarQA.fixture() { (source, access) = fixture }
        #endif
        let settings = services.settings
        let store = CalendarStore(source: source, access: access, settings: settings)
        let scheduler = MeetingScheduler(events: { store.events }, leadMinutes: { settings[CalendarSettings.leadMinutes] })
        let opener = WorkspaceURLOpener()
        let launcher = JoinLauncher(opener: opener, joinsInApp: { settings[CalendarSettings.joinsInApp] })
        return CalendarModel(store: store, scheduler: scheduler, launcher: launcher, settings: settings,
                             environment: services.environment, app: services.app, opener: opener)
    }
}
