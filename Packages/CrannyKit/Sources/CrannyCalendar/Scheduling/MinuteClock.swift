// CrannyCalendar/Scheduling/MinuteClock.swift — the time for minute-resolution text ("in 4m", "12m left") and
// the meeting ring. It wakes once per minute, exactly when the shown value changes (minutes counted from the
// anchor: an event's start or end), and only while the view is on screen (ARCHITECTURE.md §7.4: "a
// once-per-minute tick only while its activity is visible"). Not a `TimelineView`: those keep SwiftUI
// updating at the display rate (§9.2).
import Foundation
import SwiftUI

struct MinuteClock<Content: View>: View {
    private let anchor: Date
    private let content: (Date) -> Content
    @State private var date = Date()

    /// - Parameter anchor: values change at `anchor ± k × 60 s` (e.g. the event's start for "in 4m").
    init(anchor: Date, @ViewBuilder content: @escaping (Date) -> Content) {
        self.anchor = anchor
        self.content = content
    }

    var body: some View {
        content(date)
            .task(id: anchor) {
                date = Date()
                while !Task.isCancelled {
                    let wait = Self.nextTick(after: Date(), anchor: anchor).timeIntervalSinceNow
                    do {
                        try await Task.sleep(for: .milliseconds(Int64(max(wait, 0.05) * 1000)), tolerance: .milliseconds(250))
                    } catch {
                        return                                                // the view went away
                    }
                    date = Date()
                }
            }
    }

    /// The first instant after `now` that lies a whole number of minutes from `anchor`, plus a few
    /// milliseconds so the new value is already current when the view redraws.
    nonisolated static func nextTick(after now: Date, anchor: Date) -> Date {
        let elapsed = now.timeIntervalSince(anchor)
        let steps = (elapsed / 60).rounded(.down) + 1
        return anchor.addingTimeInterval(steps * 60 + 0.02)
    }
}

/// Whole minutes for display, counted the way people read a countdown: 4 min 10 s before the start is "in 5m",
/// 3 min 59 s is "in 4m", anything under a minute is "in 1m"; elapsed time counts down to whole minutes.
nonisolated enum MinuteMath {
    /// Minutes until `date` (≥ 1 while it is in the future, 0 once it has passed).
    static func minutesUntil(_ date: Date, from now: Date) -> Int {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }

    /// Whole minutes since `date` (0 in the first minute).
    static func minutesSince(_ date: Date, to now: Date) -> Int {
        max(Int((now.timeIntervalSince(date) / 60).rounded(.down)), 0)
    }

    /// Fraction of `start…end` that has passed at `now`, 0…1.
    static func progress(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return now >= end ? 1 : 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
}

#Preview("Minute clock") {
    MinuteClock(anchor: Date().addingTimeInterval(245)) { now in
        Text(verbatim: "\(MinuteMath.minutesUntil(Date().addingTimeInterval(245), from: now)) min")
            .foregroundStyle(.white)
    }
    .padding()
    .background(.black)
}
