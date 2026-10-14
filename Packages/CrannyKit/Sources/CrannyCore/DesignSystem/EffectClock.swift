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
public struct EffectClock<Content: View>: View {
    private let minimumInterval: Double?
    private let content: (Date) -> Content
    @State private var date = Date()

    public init(minimumInterval: Double?, @ViewBuilder content: @escaping (Date) -> Content) {
        self.minimumInterval = minimumInterval
        self.content = content
    }

    public var body: some View {
        content(date)
            .task(id: minimumInterval) {
                guard let interval = minimumInterval, interval > 0 else { return }
                let clock = ContinuousClock()
                var deadline = clock.now
                date = Date()
                while !Task.isCancelled {
                    deadline = Self.nextDeadline(after: deadline, now: clock.now, interval: interval)
                    do {
                        try await Task.sleep(until: deadline, tolerance: .seconds(interval / 8), clock: clock)
                    } catch {
                        return                                                   // cancelled: paused or gone
                    }
                    date = Date()
                }
            }
    }

    /// The next frame: one interval after the previous one, or one interval from now when frames were
    /// missed (sleep, a busy main thread), so the clock never fires a burst of catch-up frames.
    nonisolated static func nextDeadline(after previous: ContinuousClock.Instant, now: ContinuousClock.Instant,
                                         interval: Double) -> ContinuousClock.Instant {
        let next = previous.advanced(by: .seconds(interval))
        return next > now ? next : now.advanced(by: .seconds(interval))
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
