// CrannyAppShell/Services/PauseController.swift — "Pause Live Activities" (ARCHITECTURE.md §4.7, DESIGN.md §13).
// The only writer of `CoreSettings.pausedUntil` (+1 hour / tomorrow 00:00 / `.distantFuture`). The shell's
// `ShellEnvironment` derives `areLiveActivitiesPaused` from the key by observation; the arbiter then silences
// activities, peeks and delight moments while the HUD keeps working. Event-driven: one sleep to the deadline
// clears the key, so a pause that has ended never lingers in Settings or the menu.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.activities)

/// How long a pause lasts (the menu bar's Pause Live Activities ▸ submenu).
nonisolated enum PauseDuration: String, CaseIterable, Sendable {
    case oneHour, untilTomorrow, untilResumed

    /// The `pausedUntil` value for a pause that starts at `now`: +1 h, the start of the next local day, or
    /// `.distantFuture` ("until I resume").
    func deadline(from now: Date, calendar: Calendar) -> Date {
        switch self {
        case .oneHour: now.addingTimeInterval(3600)
        case .untilTomorrow: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        case .untilResumed: .distantFuture
        }
    }
}

/// What a running pause looks like to the user (the status line of the menu).
nonisolated enum PauseStatus: Equatable, Sendable {
    case notPaused
    /// Ends later today, at that time.
    case untilLaterToday(Date)
    /// Ends exactly at the start of tomorrow ("Until Tomorrow").
    case untilTomorrow
    /// Ends on another day, at that date and time (a one-hour pause started just before midnight).
    case untilDate(Date)
    case untilResumed

    init(pausedUntil: Date?, now: Date, calendar: Calendar) {
        guard let until = pausedUntil, until > now else { self = .notPaused; return }
        if until == .distantFuture {
            self = .untilResumed
        } else if until == PauseDuration.untilTomorrow.deadline(from: now, calendar: calendar) {
            self = .untilTomorrow
        } else if calendar.isDate(until, inSameDayAs: now) {
            self = .untilLaterToday(until)
        } else {
            self = .untilDate(until)
        }
    }

    var isPaused: Bool { self != .notPaused }
}

@MainActor @Observable final class PauseController {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// `now` and `calendar` are injected by tests; the app uses the wall clock and the user's calendar.
    init(settings: SettingsStore, now: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent) {
        self.settings = settings; self.now = now; self.calendar = calendar
    }

    // MARK: State (observable through the settings key)

    /// nil when not paused. A deadline in the past counts as not paused (cleared by the housekeeping below).
    var pausedUntil: Date? { settings[CoreSettings.pausedUntil].flatMap { $0 > now() ? $0 : nil } }
    var isPaused: Bool { pausedUntil != nil }
    var status: PauseStatus { PauseStatus(pausedUntil: settings[CoreSettings.pausedUntil], now: now(), calendar: calendar) }

    // MARK: Actions

    func pause(_ duration: PauseDuration) {
        let until = duration.deadline(from: now(), calendar: calendar)
        settings[CoreSettings.pausedUntil] = until
        log.info("live activities paused (\(duration.rawValue, privacy: .public))")
    }

    func resume() {
        guard settings[CoreSettings.pausedUntil] != nil else { return }
        settings[CoreSettings.pausedUntil] = nil
        log.info("live activities resumed")
    }

    /// The Pause activities shortcut: resumes a running pause, otherwise pauses for one hour (it ends by itself).
    func toggle() {
        if isPaused { resume() } else { pause(.oneHour) }
    }

    // MARK: Housekeeping (the app's instance only)

    /// Clears a pause that ended while Cranny was not running, and clears each pause when it ends, so the
    /// key always means "paused now". Reset All and Undo are followed through the observed key.
    func start() {
        token = observe({ [settings] in settings[CoreSettings.pausedUntil] }) { [weak self] _ in self?.scheduleExpiry() }
        scheduleExpiry()
    }

    func stop() {
        token = nil
        expiry?.cancel()
        expiry = nil
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        expiry = nil
        guard let until = settings[CoreSettings.pausedUntil] else { return }
        let remaining = until.timeIntervalSince(now())
        guard remaining > 0 else { settings[CoreSettings.pausedUntil] = nil; return }
        guard until != .distantFuture else { return }
        // One sleep to the deadline (the continuous clock keeps counting through system sleep), no polling.
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            if let current = self.settings[CoreSettings.pausedUntil], current <= self.now() {
                self.settings[CoreSettings.pausedUntil] = nil
                log.info("live activities resumed (pause ended)")
            }
        }
    }
}
