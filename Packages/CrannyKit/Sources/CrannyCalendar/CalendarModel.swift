// CrannyCalendar/CalendarModel.swift — the module's façade: the store, the scheduler and Join, plus what every
// surface asks of them (redaction, the allowed services, opening an event). The widget, both activities, the
// ⌘K provider and the Settings pane share one instance; samples get their own (`CalendarModel.sample`).
import CrannyCore
import Foundation
import Observation

@MainActor @Observable final class CalendarModel {
    @ObservationIgnored let store: CalendarStore
    @ObservationIgnored let scheduler: MeetingScheduler
    @ObservationIgnored let launcher: JoinLauncher
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored private let environment: any SystemEnvironment
    @ObservationIgnored private let app: any AppControl
    @ObservationIgnored private let opener: any URLOpening
    /// A sample model (Settings stage, onboarding, `#Preview`): Join and "Open in Calendar" do nothing.
    @ObservationIgnored let isSample: Bool

    /// The day the widget shows, relative to today (‹ › and the day strip); clamped to the window on read.
    var dayOffset = 0

    init(store: CalendarStore, scheduler: MeetingScheduler, launcher: JoinLauncher, settings: SettingsStore,
         environment: any SystemEnvironment, app: any AppControl, opener: any URLOpening, isSample: Bool = false) {
        self.store = store; self.scheduler = scheduler; self.launcher = launcher; self.settings = settings
        self.environment = environment; self.app = app; self.opener = opener; self.isSample = isSample
    }

    // MARK: - Reading

    /// Demo mode with "Redact calendar titles" (General ▸ Demo mode).
    var isRedacted: Bool { environment.isDemoMode && settings[CoreSettings.demoRedactsCalendar] }

    /// Services the user allows a Join button for (Settings ▸ Calendar ▸ Meeting links).
    var allowedServices: Set<MeetingService> { Set(settings[CalendarSettings.joinProviders]) }

    func link(for event: EventSnapshot) -> MeetingLink? { event.link(allowing: allowedServices) }

    /// The time minute-resolution views draw with: the `MinuteClock` tick, or the frozen instant of a sample
    /// (a sample's "in 4m" must not count down to "in 0m" on the Settings stage).
    func displayNow(_ tick: Date) -> Date { isSample ? scheduler.now : tick }

    /// "Now" for values computed outside a view (VoiceOver values): the store's clock, or a sample's frozen instant.
    var currentTime: Date { isSample ? scheduler.now : store.clock.now() }

    /// The selectable day offsets: −daysBehind … +daysAhead.
    var dayRange: ClosedRange<Int> {
        -EventWindow.clampDays(settings[CalendarSettings.daysBehind])...EventWindow.clampDays(settings[CalendarSettings.daysAhead])
    }

    /// `dayOffset` clamped to `dayRange` (settings may have shrunk the window).
    var selectedOffset: Int { firstShownOffset(columns: 1) }

    /// The first day shown when `columns` days sit side by side (5 cells: the day and the next), clamped so the
    /// last column stays inside the window. Paging moves both columns.
    func firstShownOffset(columns: Int) -> Int {
        let range = dayRange
        let upper = max(range.upperBound - (columns - 1), range.lowerBound)
        return min(max(dayOffset, range.lowerBound), upper)
    }

    /// Whether paging by `step` days keeps every column inside the window (‹ › enabled, ← → handled).
    func canPage(_ step: Int, columns: Int = 1) -> Bool {
        let first = firstShownOffset(columns: columns) + step
        return first >= dayRange.lowerBound && first + columns - 1 <= dayRange.upperBound
    }

    /// Pages by `step` days (‹ ›, ← →); nothing when that would leave the window.
    func page(_ step: Int, columns: Int = 1) {
        guard canPage(step, columns: columns) else { return }
        dayOffset = firstShownOffset(columns: columns) + step
    }

    /// The meeting ⌘K "Join next meeting" opens: the one in progress, else the next one today, if it has a link.
    /// Read on every palette keystroke: the allowed services are read once, not once per candidate.
    var nextJoinable: (event: EventSnapshot, link: MeetingLink)? {
        let now = scheduler.now
        let candidates = store.events.filter { $0.isTimed && $0.end > now }
        let today = EventWindow.day(offset: 0, from: now, calendar: store.clock.calendar())
        let ordered = candidates.filter { $0.isInProgress(at: now) }.sorted { $0.start > $1.start }
            + candidates.filter { $0.start > now && today.contains($0.start) }
        let services = allowedServices
        for event in ordered { if let link = event.link(allowing: services) { return (event, link) } }
        return nil
    }

    // MARK: - Actions

    func join(_ event: EventSnapshot) {
        guard !isSample, let link = link(for: event) else { return }
        launcher.join(link)
    }

    /// Shows the event in Calendar (`ical://ekevent/<id>?method=show`, [UNVERIFIED] on macOS 27), or just opens
    /// Calendar.
    func openInCalendar(_ event: EventSnapshot?) {
        guard !isSample else { return }
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(":")                                   // identifiers look like "<calendar>:<event>"
        if let id = event?.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), opener.open(url) {
            return
        }
        opener.openApplication(bundleIdentifier: "com.apple.iCal")
    }

    /// "Calendars: 0 of 5 shown · Choose…" and the denied state's secondary path.
    func openCalendarSettings() {
        guard !isSample else { return }
        app.openSettings(.calendar)
    }

    /// Settings ▸ Calendar without access: the Permissions pane (Settings never shows the prompt itself).
    func openPermissionsSettings() {
        guard !isSample else { return }
        app.openSettings(.permissions)
    }

    func selectDay(_ offset: Int) {
        dayOffset = min(max(offset, dayRange.lowerBound), dayRange.upperBound)
    }
}
