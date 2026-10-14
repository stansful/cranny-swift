import AppKit
import CrannyCore
import EventKit
import Foundation
import Observation
import Testing
@testable import CrannyCalendar

/// The store against an injected `EventSource` and a `CalendarAccess` double: no EventKit, no TCC, no prompt.
@Suite @MainActor struct CalendarStoreTests {
    private let time = TestTime(T.date(h: 9, 50))
    private let center = NotificationCenter()
    private let workspace = NotificationCenter()

    private func makeStore(access: FakeAccess, source: FixtureEventSource,
                           settings: SettingsStore = CrannyServices.preview().settings) -> CalendarStore {
        CalendarStore(source: source, access: access, settings: settings, clock: time.clock,
                      center: center, workspaceCenter: workspace, reloadDelay: .milliseconds(1))
    }

    private var sampleEvents: [EventSnapshot] {
        [T.event("standup", start: T.date(h: 10), minutes: 15, link: "https://zoom.us/j/1"),
         T.event("private", start: T.date(h: 12), calendarID: "home"),
         T.event("declined", start: T.date(h: 13), declined: true),
         T.event("tomorrow", start: T.date(2026, 10, 15, h: 9))]
    }

    @Test func withoutAccessNothingIsFetched() async {
        let source = FixtureEventSource(events: sampleEvents)
        let access = FakeAccess(.notDetermined)
        let store = makeStore(access: access, source: source)
        await store.reload()
        #expect(store.phase == .needsAccess(.notDetermined))
        #expect(store.events.isEmpty)
        #expect(await source.eventFetches == 0)
        #expect(access.requests == 0)                                      // never asks on its own
    }

    @Test func loadsTheWindowAndFiltersOnRead() async throws {
        let settings = CrannyServices.preview().settings
        let source = FixtureEventSource(events: sampleEvents, calendars: [CalendarInfo(id: "work", title: "Work", color: .white, sourceTitle: "iCloud")])
        let store = makeStore(access: FakeAccess(.granted), source: source, settings: settings)
        await store.reload()
        #expect(store.phase == .ready)
        #expect(await source.lastInterval == DateInterval(start: T.date(h: 0), end: T.date(2026, 10, 16, h: 0)))
        #expect(store.events.map(\.id) == ["standup", "private", "tomorrow"])     // declined is gone
        #expect(store.calendars.count == 1)

        settings[CalendarSettings.hiddenCalendarIDs] = ["home"]
        #expect(store.events.map(\.id) == ["standup", "tomorrow"])
        #expect(await source.eventFetches == 1)                                    // hiding refetches nothing
    }

    @Test func cachedEventsStillObserveTheirInputs() async throws {
        let settings = CrannyServices.preview().settings
        let store = makeStore(access: FakeAccess(.granted), source: FixtureEventSource(events: sampleEvents), settings: settings)
        await store.reload()
        #expect(store.events.map(\.id) == ["standup", "private", "tomorrow"])
        // A second read is served from the cache: it must still register the filter keys and `fetched`.
        let changed = Flag()
        withObservationTracking { _ = store.events } onChange: { changed.isSet = true }
        settings[CalendarSettings.includesAllDay] = false
        #expect(changed.isSet)
        #expect(store.events.map(\.id) == ["standup", "private", "tomorrow"])     // none of them is all-day
        settings[CalendarSettings.hiddenCalendarIDs] = ["work"]
        #expect(store.events.map(\.id) == ["private"])
        let reloaded = Flag()
        withObservationTracking { _ = store.events } onChange: { reloaded.isSet = true }
        store.preload(events: [T.event("new", start: T.date(h: 11), calendarID: "home")], calendars: [])
        #expect(reloaded.isSet)
        #expect(store.events.map(\.id) == ["new"])
    }

    @Test func windowSettingsRefetch() async throws {
        let settings = CrannyServices.preview().settings
        let source = FixtureEventSource(events: sampleEvents)
        let store = makeStore(access: FakeAccess(.granted), source: source, settings: settings)
        store.start()
        await settle()
        settings[CalendarSettings.daysBehind] = 2
        // The reload runs at utility priority: wait for it (generous bound, suites run in parallel), not a fixed time.
        let widened = T.date(2026, 10, 12, h: 0)
        var waits = 0
        while await source.lastInterval?.start != widened, waits < 500 {
            waits += 1
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await source.lastInterval?.start == widened)
        store.stop()
    }

    @Test func requestAccessOnlyFromTheButtonThenLoads() async throws {
        let source = FixtureEventSource(events: sampleEvents)
        let access = FakeAccess(.notDetermined)
        let store = makeStore(access: access, source: source)
        store.start()
        await settle()
        #expect(await source.eventFetches == 0)
        await store.requestAccess()
        await settle(10)
        #expect(access.requests == 1)
        #expect(await source.resets == 1)                                           // a fresh EKEventStore after the grant
        #expect(store.phase == .ready)
        #expect(!store.events.isEmpty)
        store.stop()
    }

    @Test func deniedOpensSystemSettingsInsteadOfPrompting() async {
        let access = FakeAccess(.denied)
        let store = makeStore(access: access, source: FixtureEventSource())
        await store.requestAccess()
        #expect(access.requests == 0)
        #expect(access.settingsOpened == 1)
        store.openPrivacySettings()
        #expect(access.settingsOpened == 2)
        #expect(PermissionKind.calendar.settingsURL?.absoluteString.hasSuffix("Privacy_Calendars") == true)
    }

    @Test func accessGrantedElsewhereIsPickedUp() async throws {
        let source = FixtureEventSource(events: sampleEvents)
        let access = FakeAccess(.denied)
        let store = makeStore(access: access, source: source)
        store.start()
        await settle()
        access.status = .granted                                                   // e.g. after `refresh()`
        await settle(10)
        #expect(store.phase == .ready)
        #expect(await source.resets == 1)
        access.status = .denied
        await settle(10)
        #expect(store.events.isEmpty)
        #expect(store.phase == .needsAccess(.denied))
        store.stop()
    }

    @Test func errorsAreShownAndRetried() async throws {
        let source = FixtureEventSource(events: sampleEvents, failure: .unavailable)
        let store = makeStore(access: FakeAccess(.granted), source: source)
        await store.reload()
        #expect(store.phase == .failed(.unavailable))
        #expect(CalendarError.unavailable.errorDescription?.isEmpty == false)
        await source.set(failure: nil)
        await store.reload()
        #expect(store.phase == .ready)
    }

    @Test func systemNotificationsAskForAReload() async throws {
        let store = makeStore(access: FakeAccess(.granted), source: FixtureEventSource(events: sampleEvents))
        store.start()
        await settle()
        let before = store.reloadRequests
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            center.post(name: name, object: nil)
        }
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        await settle()
        #expect(store.reloadRequests == before + 5)
        store.stop()
        center.post(name: .EKEventStoreChanged, object: nil)
        await settle()
        #expect(store.reloadRequests == before + 5)                                 // stopped: no observers left
    }

    @Test func timeZoneChangeMovesTheWindow() async throws {
        // The clock's calendar follows the system zone (`autoupdatingCurrent` in the app); a reload re-windows.
        let zoned = ZonedClock(zone: "Europe/Berlin", now: T.date(h: 23, 30))
        let source = FixtureEventSource()
        let store = CalendarStore(source: source, access: FakeAccess(.granted), settings: CrannyServices.preview().settings,
                                  clock: zoned.clock, center: center, workspaceCenter: workspace)
        await store.reload()
        #expect(store.window.start == T.date(h: 0))
        zoned.zone = "Asia/Tokyo"                                                    // already the 15th there
        await store.reload()
        #expect(store.window.start == T.date(2026, 10, 15, h: 0, zone: "Asia/Tokyo"))
    }

    @Test func allCalendarsHiddenIsDetected() async throws {
        let settings = CrannyServices.preview().settings
        let calendars = [CalendarInfo(id: "work", title: "Work", color: .white, sourceTitle: "iCloud"),
                         CalendarInfo(id: "home", title: "Home", color: .white, sourceTitle: "iCloud"),
                         CalendarInfo(id: "bd", title: "Birthdays", color: .white, sourceTitle: "Other", isBirthdays: true)]
        let store = makeStore(access: FakeAccess(.granted), source: FixtureEventSource(calendars: calendars), settings: settings)
        await store.reload()
        #expect(store.visibleCalendarCount == 2)                                     // birthdays are off by default
        settings[CalendarSettings.hiddenCalendarIDs] = ["work", "home"]
        #expect(store.visibleCalendarCount == 0)
    }
}

/// Set by an observation's `onChange` (which may run on any thread).
nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// A clock whose calendar's time zone a test can change.
nonisolated final class ZonedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _zone: String
    let now: Date
    init(zone: String, now: Date) { _zone = zone; self.now = now }
    var zone: String {
        get { lock.withLock { _zone } }
        set { lock.withLock { _zone = newValue } }
    }
    var clock: CalendarClock { CalendarClock(now: { [now] in now }, calendar: { [self] in T.calendar(self.zone) }) }
}
