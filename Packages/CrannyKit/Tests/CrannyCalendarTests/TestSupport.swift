import CrannyCore
import Foundation
import Observation
@testable import CrannyCalendar

/// Fixed calendars and dates so tests never depend on the machine's time zone or the wall clock.
nonisolated enum T {
    static func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone) ?? .gmt
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// `2026-10-14 10:00` in `zone` (plus `minutes`).
    static func date(_ y: Int = 2026, _ m: Int = 10, _ d: Int = 14, h: Int = 10, _ min: Int = 0, s: Int = 0,
                     zone: String = "Europe/Berlin") -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s)) ?? Date(timeIntervalSince1970: 0)
    }

    static func event(_ id: String, start: Date, minutes: Double = 30, allDay: Bool = false, calendarID: String = "work",
                      title: String? = nil, link: String? = nil, cancelled: Bool = false, declined: Bool = false,
                      birthday: Bool = false) -> EventSnapshot {
        EventSnapshot(id: id, title: title ?? id, start: start, end: start.addingTimeInterval(minutes * 60), isAllDay: allDay,
                      calendarID: calendarID, color: RGB(hex: 0x1BADF8),
                      links: link.flatMap(URL.init(string:)).flatMap { MeetingLinkDetector.classify($0) }.map { [$0] } ?? [],
                      isCancelled: cancelled, isDeclined: declined, isBirthday: birthday)
    }
}

/// A clock tests can move. `@unchecked Sendable`: guarded by a lock (the scheduler reads it from its task).
nonisolated final class TestTime: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    let calendar: Calendar
    init(_ date: Date, calendar: Calendar = T.calendar()) { value = date; self.calendar = calendar }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
    var clock: CalendarClock {
        CalendarClock(now: { [self] in self.now }, calendar: { [calendar] in calendar })
    }
}

/// `CalendarAccess` that never prompts: records what the store asked for.
@MainActor @Observable final class FakeAccess: CalendarAccess {
    var status: PermissionStatus
    var requestResult: PermissionStatus = .granted
    private(set) var requests = 0
    private(set) var settingsOpened = 0
    private(set) var refreshes = 0
    init(_ status: PermissionStatus) { self.status = status }
    func request() async -> PermissionStatus { requests += 1; status = requestResult; return status }
    func refresh() { refreshes += 1 }
    func openSystemSettings() { settingsOpened += 1 }
}

/// `URLOpening` that records instead of launching anything.
@MainActor final class RecordingOpener: URLOpening {
    var installedSchemes: Set<String> = []
    var opens = true
    private(set) var opened: [URL] = []
    func applicationURL(toOpen url: URL) -> URL? {
        installedSchemes.contains(url.scheme?.lowercased() ?? "") ? URL(fileURLWithPath: "/Applications/Fake.app") : nil
    }
    func open(_ url: URL) -> Bool { opened.append(url); return opens }
    private(set) var launchedApps: [String] = []
    func openApplication(bundleIdentifier: String) -> Bool { launchedApps.append(bundleIdentifier); return true }
}

/// Lets observation callbacks, notification blocks and short tasks run.
@MainActor func settle(_ rounds: Int = 6) async {
    for _ in 0..<rounds {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// `AppControl` that records which Settings panes were opened.
@MainActor @Observable final class RecordingAppControl: AppControl {
    private(set) var openedSettings: [SettingsPageID?] = []
    var loginItem: LoginItemState = .disabled
    var update: UpdateState = .idle
    func setLaunchAtLogin(_ enabled: Bool) {}
    func checkForUpdates() {}
    func shortcutState(_ id: ShortcutID) -> ShortcutState { .off }
    func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { .off }
    func openSettings(_ page: SettingsPageID?) { openedSettings.append(page) }
    func showWelcome() {}
    func startTutorial() {}
    func showOnNotch(_ state: PreviewStageState) {}
    func resetAllSettings() {}
    func quit() {}
}

/// A live model over `events` at `time` (Berlin calendar): fixture source, fake access, recording opener and app,
/// a scheduler that never wakes on its own. No EventKit, no TCC, no wall clock.
@MainActor func makeModel(_ events: [EventSnapshot], time: TestTime, services: CrannyServices = .preview(),
                          access: FakeAccess = FakeAccess(.granted), app: RecordingAppControl = RecordingAppControl(),
                          opener: RecordingOpener = RecordingOpener()) async -> CalendarModel {
    let store = CalendarStore(source: FixtureEventSource(events: events), access: access, settings: services.settings,
                              clock: time.clock, center: NotificationCenter(), workspaceCenter: NotificationCenter())
    await store.reload()
    let scheduler = MeetingScheduler(events: { store.events }, leadMinutes: { services.settings[CalendarSettings.leadMinutes] },
                                     clock: time.clock, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    scheduler.replan()
    let launcher = JoinLauncher(opener: opener, joinsInApp: { services.settings[CalendarSettings.joinsInApp] })
    return CalendarModel(store: store, scheduler: scheduler, launcher: launcher, settings: services.settings,
                         environment: services.environment, app: app, opener: opener)
}
