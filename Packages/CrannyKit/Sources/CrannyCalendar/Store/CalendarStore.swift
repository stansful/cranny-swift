// CrannyCalendar/Store/CalendarStore.swift — the module's model of the user's events (ARCHITECTURE.md §7.4).
// Fetches the window `today − daysBehind … today + daysAhead` from an `EventSource` off the main actor, keeps
// the unfiltered result and filters on read, so hiding a calendar never refetches. Event-driven only: it reloads
// on calendar-database changes, wake, day change, clock and time-zone changes, access changes and window
// settings — never on a timer.
import AppKit
import CrannyCore
import EventKit
import Foundation
import Observation
import os

private let log = Log.logger(.calendar)

@MainActor @Observable final class CalendarStore {
    /// What the widget shows besides content.
    enum Phase: Equatable {
        case needsAccess(PermissionStatus)
        case loading
        case ready
        case failed(CalendarError)
    }

    /// Every occurrence in `window`, unfiltered.
    private(set) var fetched: [EventSnapshot] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var window: DateInterval
    private(set) var hasLoaded = false
    private(set) var error: CalendarError?
    /// Bumps after every finished load, even when nothing changed (the scheduler re-plans on it: the clock moved).
    private(set) var loadCount = 0
    /// Bumps whenever something asked for a reload (tests observe it without waiting for the debounce).
    private(set) var reloadRequests = 0

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let clock: CalendarClock
    @ObservationIgnored private let source: any EventSource
    @ObservationIgnored private let access: any CalendarAccess
    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private let workspaceCenter: NotificationCenter
    @ObservationIgnored private let debouncer: Debouncer
    @ObservationIgnored private var tokens: [ObservationToken] = []
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAccess: PermissionStatus?
    @ObservationIgnored private(set) var isStarted = false

    init(source: any EventSource, access: any CalendarAccess, settings: SettingsStore, clock: CalendarClock = .live,
         center: NotificationCenter = .default, workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         reloadDelay: Duration = .milliseconds(300)) {
        self.source = source; self.access = access; self.settings = settings; self.clock = clock
        self.center = center; self.workspaceCenter = workspaceCenter
        debouncer = Debouncer(delay: reloadDelay)
        window = EventWindow.interval(containing: clock.now(), daysBehind: settings[CalendarSettings.daysBehind],
                                      daysAhead: settings[CalendarSettings.daysAhead], calendar: clock.calendar())
    }

    // MARK: - Reading

    var accessStatus: PermissionStatus { access.status }

    var phase: Phase {
        let status = access.status
        guard status == .granted else { return .needsAccess(status) }
        if let error { return .failed(error) }
        return hasLoaded ? .ready : .loading
    }

    /// Filtered by the user's settings and sorted (observes the filter keys).
    var events: [EventSnapshot] { EventFilter(settings: settings).apply(fetched) }

    /// Calendars that are shown / all calendars (the "0 of 5 shown" state, Settings).
    var visibleCalendarCount: Int {
        let hidden = Set(settings[CalendarSettings.hiddenCalendarIDs])
        return calendars.filter { !hidden.contains($0.id) && (!$0.isBirthdays || settings[CalendarSettings.includesBirthdays]) }.count
    }

    // MARK: - Lifecycle

    /// Starts observing and loads once. Called from `registry.onLaunch` (never from `register`).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        lastAccess = access.status
        tokens.append(observe({ [access] in access.status }) { [weak self] status in self?.accessChanged(to: status) })
        tokens.append(observe({ [settings] in [settings[CalendarSettings.daysBehind], settings[CalendarSettings.daysAhead]] }) { [weak self] _ in
            self?.requestReload()
        })
        let names: [Notification.Name] = [.EKEventStoreChanged, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange]
        for name in names { addObserver(center, name) }
        addObserver(workspaceCenter, NSWorkspace.didWakeNotification)
        Task { await reload() }
    }

    func stop() {
        tokens.removeAll()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        debouncer.cancel()
        isStarted = false
    }

    /// Coalesces bursts (EventKit posts several changes per sync) into one reload.
    func requestReload() {
        reloadRequests += 1
        debouncer.schedule { [weak self] in await self?.reload() }
    }

    /// Fetches the window now. Results of a reload that a newer one overtook are dropped.
    func reload() async {
        let now = clock.now()
        let interval = EventWindow.interval(containing: now, daysBehind: settings[CalendarSettings.daysBehind],
                                            daysAhead: settings[CalendarSettings.daysAhead], calendar: clock.calendar())
        generation += 1
        let current = generation
        guard access.status == .granted else {
            clear(window: interval)
            loadCount += 1
            return
        }
        do {
            async let loadedCalendars = source.calendars()
            let loadedEvents = try await source.events(in: interval)
            let calendarList = try await loadedCalendars
            guard current == generation else { return }
            if fetched != loadedEvents { fetched = loadedEvents }
            if calendars != calendarList { calendars = calendarList }
            if window != interval { window = interval }
            if error != nil { error = nil }
            hasLoaded = true
            log.info("loaded \(loadedEvents.count, privacy: .public) events from \(calendarList.count, privacy: .public) calendars")
        } catch {
            guard current == generation else { return }
            self.error = (error as? CalendarError) ?? .unavailable
            log.error("loading events failed: \(error.localizedDescription, privacy: .public)")
        }
        loadCount += 1
    }

    // MARK: - Access (the prompt only from the widget's inline "Show your events")

    /// The "Show your events" button: the system prompt, then a load if granted.
    func requestAccess() async {
        guard access.status == .notDetermined else {
            if access.status == .denied { access.openSystemSettings() }
            return
        }
        let status = await access.request()
        log.info("calendar access: \(status.rawValue, privacy: .public)")
        accessChanged(to: status)
    }

    func openPrivacySettings() { access.openSystemSettings() }

    /// Re-reads the access status (the user may have flipped it in System Settings while Cranny ran).
    func refreshAccess() { access.refresh() }

    /// Samples and previews: shows these values as if they had just been loaded (no source, no observers).
    func preload(events: [EventSnapshot], calendars: [CalendarInfo]) {
        fetched = events
        self.calendars = calendars
        hasLoaded = true
        loadCount += 1
    }

    // MARK: - Internals

    private func accessChanged(to status: PermissionStatus) {
        guard status != lastAccess else { return }
        lastAccess = status
        if status == .granted {
            // A store created before access was granted never sees events: recreate it (ARCHITECTURE.md §7.4).
            Task { [source] in
                await source.reset()
                await self.reload()
            }
        } else {
            Task { await reload() }
        }
    }

    private func clear(window interval: DateInterval) {
        if !fetched.isEmpty { fetched = [] }
        if !calendars.isEmpty { calendars = [] }
        if window != interval { window = interval }
        hasLoaded = false
        error = nil
    }

    private func addObserver(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestReload() }                       // queue: .main
        }
        observers.append((center, observer))
    }
}
