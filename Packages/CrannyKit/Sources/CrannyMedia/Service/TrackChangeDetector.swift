// CrannyMedia/Service/TrackChangeDetector.swift — when does `trackChangeCount` increment (ARCHITECTURE.md §6.5):
// the track key changed, the new key held for 300 ms (players send partial metadata in bursts), the session is
// playing, and it is not the first snapshot after launch. Pure: the service feeds it and sleeps to the deadline.
import CrannyCore
import Foundation

nonisolated struct TrackChangeDetector: Equatable, Sendable {
    static let debounce: Duration = .milliseconds(300)

    /// The key the last counted (or baseline) track had; nil = nothing playing.
    private(set) var settledKey: String?
    /// A changed key waiting for the debounce.
    private(set) var pendingKey: String?
    private var hasBaseline = false

    /// Feed every snapshot. Returns true when a debounce must be (re)started for `pendingKey`.
    mutating func observe(_ nowPlaying: NowPlaying?) -> Bool {
        let key = nowPlaying?.trackKey
        guard hasBaseline else {
            hasBaseline = true             // the first snapshot after launch never counts
            settledKey = key
            return false
        }
        guard key != settledKey else {
            pendingKey = nil               // back to the settled track (seek glitch, partial burst)
            return false
        }
        guard let key else {
            settledKey = nil               // the session ended: a later track counts again
            pendingKey = nil
            return false
        }
        guard key != pendingKey else { return false }
        pendingKey = key
        return true
    }

    /// The debounce elapsed: true = count a track change. `current` is the latest snapshot.
    mutating func debounceElapsed(current: NowPlaying?) -> Bool {
        guard let pending = pendingKey, let current, current.trackKey == pending else { return false }
        pendingKey = nil
        settledKey = pending
        return current.isPlaying           // a change while paused settles silently (no peek)
    }
}
