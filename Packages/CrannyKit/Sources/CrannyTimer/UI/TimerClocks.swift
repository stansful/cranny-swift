// CrannyTimer/UI/TimerClocks.swift — how timer views get their time (ARCHITECTURE.md §9.2, open issue 2 of §10.1).
// No `TimelineView`: with `.animation(minimumInterval:)` SwiftUI keeps updating at the display's refresh rate and only
// filters the content. Instead:
//  • digits use `CountdownClock`: one sleep to the exact moment the shown second changes (1 Hz, aligned to the
//    deadline, so "4:59" never lags), and no wake-up at all while paused, idle or done;
//  • rings use `RingClock` (restarted when the deadline moves) at `RingCadence`: as often as the arc moves about one
//    device pixel, at most 4 × per second (a 1-minute timer in the widget), every 15–30 s for a long timer in the
//    band, and not at all unless running. The period is snapped to whole seconds (or ½, ⅓, ¼ s) and anchored to the
//    deadline like the digits, so ring frames land on the digits' own wake-ups: one timer fire and one render
//    instead of two;
//  • VoiceOver's "time left" (`refreshesSpokenTime`): the countdown's 1-Hz tick, only while VoiceOver runs.
// All stop as soon as their view leaves the screen.
import CrannyCore
import Foundation
import SwiftUI

/// Calls `content` with the current date whenever the whole seconds left until `deadline` change.
/// `deadline == nil` = frozen: no wake-ups.
struct CountdownClock<Content: View>: View {
    let deadline: Date?
    @ViewBuilder let content: (Date) -> Content
    @State private var now = Date()

    var body: some View {
        content(now)
            .task(id: deadline) {
                now = Date()
                guard let deadline else { return }
                await CountdownTick.run(until: deadline) { now = Date() }
            }
    }
}

nonisolated enum CountdownTick {
    /// Wake slightly after the boundary, so the first read already shows the new second.
    static let margin: TimeInterval = 0.02
    /// How late a wake-up may come. The ring uses the same, so its wake-ups and the digits' fire together.
    static let tolerance: Duration = .milliseconds(40)

    /// The next instant the rounded-up seconds left change (`deadline − (⌈left⌉ − 1)`), or nil once the deadline
    /// has passed (the last wake renders "0:00").
    static func next(after now: Date, deadline: Date) -> Date? {
        let left = deadline.timeIntervalSince(now)
        guard left > 0 else { return nil }
        return deadline.addingTimeInterval(-(left.rounded(.up) - 1) + margin)
    }

    /// Sleeps to each change of the shown second and calls `tick` (the last call is just after the deadline).
    /// Returns when the deadline has passed or the task is cancelled (paused, changed or off screen).
    @MainActor static func run(until deadline: Date, _ tick: @MainActor () -> Void) async {
        while let wake = next(after: Date(), deadline: deadline) {
            do {
                try await Task.sleep(for: .seconds(max(wake.timeIntervalSinceNow, 0)), tolerance: tolerance)
            } catch {
                return
            }
            tick()
        }
    }
}

extension View {
    /// While VoiceOver runs and `model`'s timer runs, refreshes `TimerModel.spokenSeconds` at each second boundary,
    /// so an accessibility value computed from `spokenSecondsLeft` (the widget ring, the running activity) never goes
    /// stale. Put it on a view that is on screen whenever that value can be read. Without VoiceOver: no wake-ups.
    func refreshesSpokenTime(_ model: TimerModel) -> some View {
        modifier(SpokenTimeRefresh(model: model))
    }
}

private struct SpokenTimeRefresh: ViewModifier {
    @Environment(\.cranny) private var theme
    let model: TimerModel

    func body(content: Content) -> some View {
        let deadline = theme.voiceOverRunning ? model.state.endDate : nil
        content.task(id: deadline) {
            guard let deadline else { return }
            model.refreshSpokenTime()
            await CountdownTick.run(until: deadline) { model.refreshSpokenTime() }
        }
    }
}

nonisolated enum RingCadence {
    /// Never faster than 4 redraws per second: each redraw renders the open panel once (≈ 3–4 ms of CPU, measured),
    /// so even a 1-minute timer stays near 1 % CPU. Longer timers redraw less often than once a second.
    static let fastest: Double = 0.25
    /// Never slower than this (s).
    static let slowest: Double = 30

    /// Seconds between redraws of a ring of `diameter` points while a run of `total` seconds counts down: the time
    /// its arc needs to travel about one device pixel.
    static func interval(total: TimeInterval, diameter: CGFloat, displayScale: CGFloat) -> Double {
        let pixels = Double.pi * Double(max(diameter, 1)) * Double(max(displayScale, 1))
        return min(max(max(total, 0) / pixels, fastest), slowest)
    }

    /// `interval` snapped to a period that divides or is a whole number of seconds (0.54 → 0.5, 2.98 → 3, 0.3 → ⅓), so
    /// a ring anchored to the deadline redraws exactly when the digits change (or halfway between). The arc still
    /// moves about one device pixel per frame.
    static func aligned(_ interval: Double) -> Double {
        let snapped = interval >= 1 ? interval.rounded() : 1 / max((1 / interval).rounded(), 1)
        return min(max(snapped, fastest), slowest)
    }

    /// The next frame of a ring counting down to `deadline` at `period`: just after the next boundary
    /// `deadline − k × period` (k ≥ 0), or nil once the deadline has passed (the last frame lands just after it, like
    /// the digits' "0:00"). With a period of 1 s this is exactly `CountdownTick.next`.
    static func nextFrame(after now: Date, deadline: Date, period: Double) -> Date? {
        let left = deadline.timeIntervalSince(now)
        guard left > 0, period > 0 else { return nil }
        let boundary = (left / period).rounded(.up) - 1
        return deadline.addingTimeInterval(-boundary * period + CountdownTick.margin)
    }
}

/// Calls `content` with the current date at every `deadline − k × period` (plus `CountdownTick.margin`) until the
/// deadline (`RingCadence.nextFrame`). The digits' clock wakes at `deadline − n` seconds with the same margin and
/// tolerance, so with a whole-second (or ½, ⅓, ¼ s) period every ring frame shares a wake-up and a render with the
/// digits. `period == nil` (or no deadline) = frozen: no wake-ups. A new deadline or period redraws at once with the
/// current date ("+1 min" or a resume never waits for a 30-s tick). Stops when its view leaves the screen.
struct RingClock<Content: View>: View {
    let deadline: Date?
    let period: Double?
    @ViewBuilder let content: (Date) -> Content
    @State private var now = Date()

    private struct Schedule: Hashable {
        var deadline: Date?
        var period: Double?
    }

    var body: some View {
        content(now)
            .task(id: Schedule(deadline: deadline, period: period)) {
                now = Date()
                guard let deadline, let period, period > 0 else { return }
                while let wake = RingCadence.nextFrame(after: Date(), deadline: deadline, period: period) {
                    do {
                        try await Task.sleep(for: .seconds(max(wake.timeIntervalSinceNow, 0)), tolerance: CountdownTick.tolerance)
                    } catch {
                        return                                                   // paused, changed or off screen
                    }
                    now = Date()
                }
            }
    }
}

/// A countdown ring (Core's `ProgressRing` in `warning`) that redraws only at `RingCadence`, and not at all unless
/// the timer runs. Phase changes animate (it fills on start and on done, drains on stop); ticks never do.
struct TimerRing: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let state: TimerState
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let cadence = state.isRunning
            ? RingCadence.aligned(RingCadence.interval(total: state.total, diameter: diameter, displayScale: displayScale)) : nil
        // Restarts (and redraws at once) when the deadline moves: "+1 min" or a resume never waits for a 30-s tick.
        RingClock(deadline: state.endDate, period: cadence) { date in
            ProgressRing(progress: state.progress(at: date), color: theme.palette.warning, lineWidth: lineWidth)
        }
        .frame(width: diameter, height: diameter)
        .animation(theme.animation(.commit), value: TimerRingPhase(state.phase))
        .accessibilityHidden(true)
    }
}

/// The phase without its dates: what the ring animates on.
enum TimerRingPhase: Equatable {
    case idle, running, paused, done
    init(_ phase: TimerPhase) {
        switch phase {
        case .idle: self = .idle
        case .running: self = .running
        case .paused: self = .paused
        case .done: self = .done
        }
    }
}

#Preview("Clocks · countdown digits and rings") {
    let now = Date()
    let running = TimerState(phase: .running(endDate: now.addingTimeInterval(65)), total: 90)
    VStack(spacing: Space.l) {
        CountdownClock(deadline: running.endDate) { date in
            Text(verbatim: TimerFormat.clock(running.displayedSeconds(at: date))).crannyFont(.numeral)
        }
        HStack(spacing: Space.l) {
            TimerRing(state: running, diameter: 16, lineWidth: StrokeWidth.ringCompact)
            TimerRing(state: running, diameter: 40, lineWidth: StrokeWidth.ring)
            TimerRing(state: TimerState(phase: .paused(remaining: 30), total: 90), diameter: 40, lineWidth: StrokeWidth.ring)
        }
    }
    .foregroundStyle(.white)
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
