// CrannyCore/DesignSystem/EffectClock.swift — the frame clock of continuously animated effects (the light
// layer, visualizers). Energy rules: ARCHITECTURE.md §9.2, DESIGN.md §4.7.
import Foundation
import SwiftUI

/// Calls `content` with the current date at most every `minimumInterval` seconds, and keeps the last date
/// while `minimumInterval` is nil (paused: closed, occluded, full screen, Reduce Motion, Low Power — pass
/// `EffectBudget.minimumInterval`). Nothing runs while paused or after the view disappears.
///
/// Use it instead of `TimelineView(.animation(minimumInterval:paused:))` (or `.periodic`) for anything that
/// changes more often than about twice a second. With those schedules SwiftUI keeps the hosting view
/// updating on every display refresh — 120 Hz on ProMotion, 240 Hz on some external displays — and only
/// filters the content by the interval. Measured with the open panel and the aurora (Release, M4 Max,
/// 240 Hz display): `TimelineView` 11.4 % CPU at 30 fps and still 9 % at 5 fps; this clock 5.0 % at
/// 30 fps and 3.6 % at 20 fps, i.e. about 1.7 ms of CPU per frame.
///
/// `restartKey`: when it changes the clock redraws at once with the current date (even while paused) and starts
/// a new cadence from there — e.g. a countdown ring whose deadline moved ("+1 min", resume) redraws now instead of
/// at its next, possibly 30-s, tick.
public struct EffectClock<Content: View>: View {
    private let minimumInterval: Double?
    private let restartKey: AnyHashable?
    private let content: (Date) -> Content
    @State private var date = Date()

    private struct Schedule: Hashable {
        var interval: Double?
        var restartKey: AnyHashable?
    }

    /// A clock at `minimumInterval` (nil = paused), restarted whenever `restartKey` changes.
    public init(minimumInterval: Double?, restartKey: AnyHashable? = nil,
                @ViewBuilder content: @escaping (Date) -> Content) {
        self.minimumInterval = minimumInterval
        self.restartKey = restartKey
        self.content = content
    }

    public var body: some View {
        content(date)
            .task(id: Schedule(interval: minimumInterval, restartKey: restartKey)) {
                if restartKey != nil { date = Date() }
                guard let interval = minimumInterval, interval > 0 else { return }
                let clock = ContinuousClock()
                var deadline = clock.now
                date = Date()
                while !Task.isCancelled {
                    deadline = FramePacing.nextDeadline(after: deadline, now: clock.now, interval: interval)
                    do {
                        try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock)
                    } catch {
                        return                                                   // cancelled: paused or gone
                    }
                    date = Date()
                }
            }
    }
}

/// Frame deadlines for paced loops (`EffectClock`).
public nonisolated enum FramePacing {
    /// The next frame: one interval after the previous one, or one interval from now when frames were missed
    /// (sleep, a busy main thread), so a paced loop never fires a burst of catch-up frames.
    public static func nextDeadline(after previous: ContinuousClock.Instant, now: ContinuousClock.Instant,
                                    interval: Double) -> ContinuousClock.Instant {
        let next = previous.advanced(by: .seconds(interval))
        return next > now ? next : now.advanced(by: .seconds(interval))
    }
}

/// Calls `content` with the current date at every `anchor + k × period` (plus 20 ms, so the new value is already
/// current when the view redraws) — e.g. minute-resolution text: "in 4m" anchored to an event's start, or the
/// wall-clock time anchored to a minute boundary (the default anchor). One sleep per period, only while the view is
/// on screen; never a `TimelineView` (ARCHITECTURE.md §9.2).
public struct AlignedClock<Content: View>: View {
    private let period: TimeInterval
    private let anchor: Date
    private let content: (Date) -> Content
    @State private var date = Date()

    /// Wall-clock minutes (and any whole-minute anchor) by default: the reference date lies on a minute boundary.
    public init(period: TimeInterval = 60, anchor: Date = Date(timeIntervalSinceReferenceDate: 0),
                @ViewBuilder content: @escaping (Date) -> Content) {
        self.period = period
        self.anchor = anchor
        self.content = content
    }

    private struct Schedule: Hashable {
        var period: TimeInterval
        var anchor: Date
    }

    public var body: some View {
        content(date)
            .task(id: Schedule(period: period, anchor: anchor)) {
                date = Date()
                guard period > 0 else { return }
                while !Task.isCancelled {
                    let wait = Self.nextTick(after: Date(), anchor: anchor, period: period).timeIntervalSinceNow
                    do {
                        try await Task.sleep(for: .seconds(max(wait, 0.05)), tolerance: .milliseconds(250))
                    } catch {
                        return                                                    // the view went away
                    }
                    date = Date()
                }
            }
    }

    /// The first instant after `now` that lies a whole number of periods from `anchor`, plus 20 ms.
    public nonisolated static func nextTick(after now: Date, anchor: Date, period: TimeInterval = 60) -> Date {
        let steps = (now.timeIntervalSince(anchor) / period).rounded(.down) + 1
        return anchor.addingTimeInterval(steps * period + 0.02)
    }
}

#Preview("Effect clock · 2 fps") {
    EffectClock(minimumInterval: 0.5) { date in
        Text(date.formatted(.dateTime.hour().minute().second()))
            .crannyFont(.caption)
            .foregroundStyle(.white)
    }
    .frame(width: 200, height: 60)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
