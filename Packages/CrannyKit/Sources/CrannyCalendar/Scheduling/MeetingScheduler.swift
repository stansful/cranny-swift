// CrannyCalendar/Scheduling/MeetingScheduler.swift — drives the meeting activities and the widget's "now".
// No polling (ARCHITECTURE.md §9.2): after every change it computes the next boundary (`MeetingTimeline`) and
// sleeps once until then; with nothing ahead there is no task at all. Per-minute text ("in 4m", "12m left") is
// ticked by `MinuteClock` in the views, only while they are on screen.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.calendar)

@MainActor @Observable final class MeetingScheduler {
    /// The instant of the last plan: changes exactly at boundaries (event starts and ends, alerts).
    private(set) var now: Date
    private(set) var state = MeetingTimeline.State.none
    /// Meaningful changes of "Meeting soon": a new upcoming event, or its last minute.
    private(set) var soonRevision = 0
    /// Meaningful changes of "Meeting in progress": a meeting started.
    private(set) var currentRevision = 0
    /// The pending wake-up (nil = nothing ahead: no task, no timer).
    private(set) var nextWake: Date?

    @ObservationIgnored private let events: @MainActor () -> [EventSnapshot]
    @ObservationIgnored private let leadMinutes: @MainActor () -> Int
    @ObservationIgnored private let clock: CalendarClock
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var tokens: [ObservationToken] = []
    @ObservationIgnored private var soonKey: String?
    @ObservationIgnored private var currentKey: String?

    /// - Parameters:
    ///   - events: the filtered events (`CalendarStore.events`); read inside observation.
    ///   - sleep: injectable for tests (default `Task.sleep`, on the continuous clock: it keeps counting while the
    ///     Mac sleeps, and the store reloads on wake anyway).
    init(events: @escaping @MainActor () -> [EventSnapshot], leadMinutes: @escaping @MainActor () -> Int,
         clock: CalendarClock = .live,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0, tolerance: .milliseconds(500)) }) {
        self.events = events; self.leadMinutes = leadMinutes; self.clock = clock; self.sleep = sleep
        now = clock.now()
    }

    /// Re-plans whenever the events, the lead time or a reload (`trigger`, e.g. `store.loadCount`) change.
    func start(trigger: @escaping @MainActor () -> Int = { 0 }) {
        guard tokens.isEmpty else { return }
        tokens.append(observe({ [events, leadMinutes] in Plan(events: events(), lead: leadMinutes(), trigger: trigger()) }) { [weak self] _ in
            self?.replan()
        })
        replan()
    }

    func stop() {
        tokens.removeAll()
        wake?.cancel()
        wake = nil
        nextWake = nil
    }

    /// Computes the state at the current time, bumps revisions on meaningful changes and schedules ONE wake-up.
    /// `scheduling: false` for samples and previews (a frozen state, no task).
    func replan(scheduling: Bool = true) {
        let time = clock.now()
        let list = events(), lead = leadMinutes()
        let next = MeetingTimeline.state(events: list, now: time, leadMinutes: lead)

        let newSoonKey = next.soon?.key
        if let newSoonKey, newSoonKey != soonKey { soonRevision += 1 }
        soonKey = newSoonKey
        let newCurrentKey = next.current?.id
        if let newCurrentKey, newCurrentKey != currentKey { currentRevision += 1 }
        currentKey = newCurrentKey

        if now != time { now = time }
        if state != next { state = next }
        guard scheduling else { return }
        schedule(MeetingTimeline.nextBoundary(events: list, now: time, leadMinutes: lead))
    }

    // MARK: - Internals

    /// What a plan depends on (the observation fires only when it changes).
    private struct Plan: Equatable {
        var events: [EventSnapshot]
        var lead: Int
        var trigger: Int
    }

    private func schedule(_ boundary: Date?) {
        guard boundary != nextWake || wake == nil else { return }
        wake?.cancel()
        wake = nil
        nextWake = boundary
        guard let boundary else { return }
        // Land just after the boundary so `state(at:)` sees the new side of it.
        let delay = max(boundary.timeIntervalSince(clock.now()), 0) + 0.05
        wake = Task { [weak self, sleep] in
            do { try await sleep(.milliseconds(Int64(delay * 1000))) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.wake = nil
            self.replan()
        }
        log.debug("next calendar wake in \(Int(delay), privacy: .public) s")
    }
}
