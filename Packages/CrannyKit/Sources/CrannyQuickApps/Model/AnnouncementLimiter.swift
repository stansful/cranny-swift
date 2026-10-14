// CrannyQuickApps/Model/AnnouncementLimiter.swift — VoiceOver announcements at most once per interval (pure, tested).
// DESIGN.md §16: announcements are rate-limited to one per 10 s; a result that arrives sooner is dropped (it still
// flashes in the notch, and the tile's accessibility value says it).
import Foundation

nonisolated struct AnnouncementLimiter: Sendable {
    let interval: TimeInterval
    private(set) var lastAnnouncement: Date?

    init(interval: TimeInterval = 10) { self.interval = interval }

    /// Whether an announcement may be posted at `now`; records it when it may.
    mutating func allows(at now: Date) -> Bool {
        if let lastAnnouncement, now.timeIntervalSince(lastAnnouncement) < interval { return false }
        lastAnnouncement = now
        return true
    }
}
