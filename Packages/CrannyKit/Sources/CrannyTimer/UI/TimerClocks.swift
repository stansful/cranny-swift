// CrannyTimer/UI/TimerClocks.swift — how timer views get their time (ARCHITECTURE.md §9.2, open issue 2 of §10.1).
// No `TimelineView`: with `.animation(minimumInterval:)` SwiftUI keeps updating at the display's refresh rate and only
// filters the content. Instead:
//  • digits use `CountdownClock`: one sleep to the exact moment the shown second changes (1 Hz, aligned to the
//    deadline, so "4:59" never lags), and no wake-up at all while paused, idle or done;
//  • rings use `RingClock` (Core's `EffectClock` technique) at `RingCadence`: as often as the arc moves about one device pixel (≈ 9 fps for
//    a 1-minute timer in the widget, every 15–30 s for a long timer in the band), paused when not running.
// Both stop as soon as their view leaves the screen.
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
                while let wake = CountdownTick.next(after: Date(), deadline: deadline) {
                    do {
                        try await Task.sleep(for: .seconds(max(wake.timeIntervalSinceNow, 0)), tolerance: .milliseconds(40))
                    } catch {
                        return                                          // cancelled: paused, changed or off screen
                    }
                    now = Date()
                }
            }
    }
}

nonisolated enum CountdownTick {
    /// Wake slightly after the boundary, so the first read already shows the new second.
    static let margin: TimeInterval = 0.02

    /// The next instant the rounded-up seconds left change (`deadline − (⌈left⌉ − 1)`), or nil once the deadline
    /// has passed (the last wake renders "0:00").
    static func next(after now: Date, deadline: Date) -> Date? {
        let left = deadline.timeIntervalSince(now)
        guard left > 0 else { return nil }
        return deadline.addingTimeInterval(-(left.rounded(.up) - 1) + margin)
    }
}

nonisolated enum RingCadence {
    /// Never faster than this (s): a 1-second timer still looks smooth without costing a display-rate redraw.
    static let fastest: Double = 1.0 / 15
    /// Never slower than this (s).
    static let slowest: Double = 30

    /// Seconds between redraws of a ring of `diameter` points while a run of `total` seconds counts down: the time
    /// its arc needs to travel about one device pixel.
    static func interval(total: TimeInterval, diameter: CGFloat, displayScale: CGFloat) -> Double {
        let pixels = Double.pi * Double(max(diameter, 1)) * Double(max(displayScale, 1))
        return min(max(max(total, 0) / pixels, fastest), slowest)
    }
}

/// Calls `content` with the current date every `interval` seconds (nil = frozen, no wake-ups). Like Core's
/// `EffectClock`, but it also restarts when `deadline` changes, so "+1 min" or a resume redraws at once instead of
/// waiting for the next (possibly 30-s) tick.
struct RingClock<Content: View>: View {
    let interval: Double?
    let deadline: Date?
    @ViewBuilder let content: (Date) -> Content
    @State private var now = Date()

    private struct Key: Hashable { var interval: Double?; var deadline: Date? }

    var body: some View {
        content(now)
            .task(id: Key(interval: interval, deadline: deadline)) {
                now = Date()
                guard let interval, interval > 0 else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval / 8)) } catch { return }
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
            ? RingCadence.interval(total: state.total, diameter: diameter, displayScale: displayScale) : nil
        RingClock(interval: cadence, deadline: state.endDate) { date in
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
