// CrannyCalendar/CalendarModel+Sample.swift — self-contained models with the sample day (`CalendarSamples`):
// the Settings "Simulate" chips and the onboarding stage (`RegisteredActivity.makeSample`), `#Preview`s and
// tests. They read the live settings and Demo mode, never touch EventKit, never schedule a wake-up and never
// open anything.
import CrannyCore
import Foundation
import Observation

/// `CalendarAccess` with a fixed answer (samples are always "granted"; previews show the other states).
@MainActor @Observable final class StaticCalendarAccess: CalendarAccess {
    var status: PermissionStatus
    init(_ status: PermissionStatus) { self.status = status }
    func request() async -> PermissionStatus { status }
    func refresh() {}
    func openSystemSettings() {}
}

extension CalendarModel {
    /// A model frozen at `now` over the sample day.
    static func sample(services: CrannyServices, now: Date = Date(), access: PermissionStatus = .granted,
                       events: [EventSnapshot]? = nil) -> CalendarModel {
        let clock = CalendarClock.fixed(now)
        let lead = services.settings[CalendarSettings.leadMinutes]
        let list = events ?? CalendarSamples.events(around: now, soonIn: min(4, lead))
        let store = CalendarStore(source: FixtureEventSource(events: list, calendars: CalendarSamples.calendars),
                                  access: StaticCalendarAccess(access), settings: services.settings, clock: clock)
        if access == .granted { store.preload(events: list, calendars: CalendarSamples.calendars) }
        let scheduler = MeetingScheduler(events: { store.events }, leadMinutes: { services.settings[CalendarSettings.leadMinutes] },
                                         clock: clock)
        scheduler.replan(scheduling: false)
        let opener = InertURLOpener()
        return CalendarModel(store: store, scheduler: scheduler,
                             launcher: JoinLauncher(opener: opener, joinsInApp: { false }), settings: services.settings,
                             environment: services.environment, app: services.app, opener: opener, isSample: true)
    }
}
