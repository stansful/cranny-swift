// CrannyMedia/Service/NowPlayingTimeline.swift — when a new snapshot only re-anchors the one on screen. Players
// re-publish their info with a fresh elapsed/timestamp pair (late artwork, buffering, some every few seconds) that
// predicts the same position; writing it to `MediaService.nowPlaying` would only invalidate every observer (the
// notch's root view, the activity, the progress views) for nothing. The bridge skips most of these itself
// (CrannyMediaBridge.m `sendState`); this also covers the Apple Events fallback and the bridge's forced refreshes.
import CrannyCore
import Foundation

extension NowPlaying {
    /// Two positions closer than this are the same on screen (the labels show whole seconds; 50 ms is 0.03 % of a
    /// 3-minute scrubber).
    nonisolated static let sameTimelineTolerance: TimeInterval = 0.05

    /// `other` equals this snapshot except for `elapsed`/`timestamp`, and both predict the same position at `now`.
    nonisolated func hasSameTimeline(as other: NowPlaying, at now: Date) -> Bool {
        guard abs(position(at: now) - other.position(at: now)) < Self.sameTimelineTolerance else { return false }
        var reanchored = self
        reanchored.elapsed = other.elapsed
        reanchored.timestamp = other.timestamp
        return reanchored == other
    }
}
