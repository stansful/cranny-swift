// CrannyMedia/Service/MediaClock.swift — the time source of the media module. Every delay (restart backoff,
// track-change debounce, the paused-media timeout, the artwork grace period) is ONE sleep to a deadline,
// never a repeating timer (ARCHITECTURE.md §9.1). Tests inject a manual clock.
import Foundation

@MainActor protocol MediaClock: AnyObject {
    var now: Date { get }
    /// Throws `CancellationError` when the calling task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// Wall time and `Task.sleep`.
@MainActor final class SystemMediaClock: MediaClock {
    var now: Date { Date() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

nonisolated extension Duration {
    /// Seconds as a `TimeInterval` (for `Date` arithmetic).
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
