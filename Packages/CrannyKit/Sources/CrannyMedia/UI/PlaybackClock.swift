// CrannyMedia/UI/PlaybackClock.swift — the time shown by the scrubber and its labels (DESIGN.md §7.1 "1:24 … −2:11").
//   • `PlaybackTime`: elapsed and remaining in whole seconds of ONE position, so they always add up to the
//     duration (215 s at 84.6 s → 1:24 and −2:11, never −2:10).
//   • `PlaybackTicker`: redraws once per second of playback, just after the position crosses a whole second, so the
//     labels never repeat or skip a second. Energy (open issue 2, ARCHITECTURE.md §10.1): the same mechanism as
//     `EffectClock(minimumInterval: 1)` — one `Task.sleep` per tick, only while playing and on screen, nothing at
//     display rate, no TimelineView — but aligned to the track instead of to when the view appeared.
import CrannyCore
import SwiftUI

nonisolated struct PlaybackTime: Equatable, Sendable {
    /// Whole seconds played.
    let elapsed: Int
    /// Whole seconds left: the duration's whole seconds minus `elapsed`.
    let remaining: Int

    init(position: TimeInterval, duration: TimeInterval) {
        let total = Self.wholeSeconds(duration)
        elapsed = min(Self.wholeSeconds(position), total)
        remaining = total - elapsed
    }

    /// Finite, non-negative and capped at a week (far beyond any track) before converting.
    private static func wholeSeconds(_ t: TimeInterval) -> Int {
        guard t.isFinite, t > 0 else { return 0 }
        return Int(min(t, 86_400 * 7).rounded(.down))
    }
}

nonisolated enum PlaybackTick {
    /// How far past the second boundary a tick lands: the sleep never wakes early, so the label reads the new
    /// second; the 100-ms tolerance only makes it later.
    static let margin: TimeInterval = 0.02
    static let tolerance: Duration = .milliseconds(100)

    /// Wall-clock seconds until the position crosses its next whole second (+ `margin`), or nil when nothing
    /// will change: paused, or at the end of the track.
    static func delay(position: TimeInterval, rate: Double, isPlaying: Bool, duration: TimeInterval?) -> TimeInterval? {
        guard isPlaying, position.isFinite else { return nil }
        if let duration, position >= duration { return nil }
        let speed = rate > 0 ? rate : 1
        let next = position.rounded(.down) + 1
        return (next - position) / speed + margin
    }
}

/// Calls `content` with the current date at every whole second of playback (see the file header).
struct PlaybackTicker<Content: View>: View {
    let nowPlaying: NowPlaying
    @ViewBuilder let content: (Date) -> Content
    @State private var date = Date()

    var body: some View {
        content(date)
            .task(id: Anchor(nowPlaying)) {
                date = Date()
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    let now = Date()
                    guard let delay = PlaybackTick.delay(position: nowPlaying.position(at: now), rate: nowPlaying.rate,
                                                         isPlaying: nowPlaying.isPlaying, duration: nowPlaying.duration) else { return }
                    do {
                        try await Task.sleep(until: clock.now.advanced(by: .seconds(delay)), tolerance: PlaybackTick.tolerance, clock: clock)
                    } catch {
                        return                                              // cancelled: gone, or a new anchor
                    }
                    date = Date()
                }
            }
    }

    /// What the ticks depend on: a seek, pause, rate change or new track restarts them.
    private struct Anchor: Equatable {
        let elapsed: TimeInterval, timestamp: Date, rate: Double, isPlaying: Bool, duration: TimeInterval?, key: String
        init(_ np: NowPlaying) {
            elapsed = np.elapsed; timestamp = np.timestamp; rate = np.rate; isPlaying = np.isPlaying
            duration = np.duration; key = np.trackKey
        }
    }
}

#Preview("Playback ticker · labels") {
    let np = SampleMedia.nowPlaying()
    PlaybackTicker(nowPlaying: np) { date in
        let time = PlaybackTime(position: np.position(at: date), duration: np.duration ?? 0)
        Text(verbatim: "\(MediaStrings.clock(TimeInterval(time.elapsed)))  \u{2212}\(MediaStrings.clock(TimeInterval(time.remaining)))")
            .crannyFont(.caption)
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
