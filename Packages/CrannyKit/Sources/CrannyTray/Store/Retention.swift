// CrannyTray/Store/Retention.swift — which items leave the Tray, and when (DESIGN.md §8.1 "Retention",
// ARCHITECTURE.md §7.8 "size and item caps"). Pure functions of the item list and a date; the store applies them.
import Foundation

nonisolated enum Retention {
    /// How long an item stays with `.afterOneDay`.
    static let oneDay: TimeInterval = 24 * 60 * 60
    /// Expiries this close together are applied in one pass (and the wake-up for them may slip by as much): an item
    /// can leave up to a minute before or after its day is up, which nobody can tell, and nearby drops cost one
    /// wake-up and one index write instead of one each.
    static let batchWindow: TimeInterval = 60

    /// Items whose time is up at `now`.
    static func expired(_ items: [TrayItem], policy: TrayRetention, now: Date) -> Set<UUID> {
        guard policy == .afterOneDay else { return [] }
        return Set(items.filter { now.timeIntervalSince($0.addedAt) >= oneDay }.map(\.id))
    }

    /// The next moment an item expires (one `Task.sleep` to it, no polling); nil = nothing will expire.
    static func nextExpiry(_ items: [TrayItem], policy: TrayRetention) -> Date? {
        guard policy == .afterOneDay else { return nil }
        return items.map { $0.addedAt.addingTimeInterval(oneDay) }.min()
    }

    /// The oldest items beyond `maxItems`. Items in `keeping` (just added) never make room for themselves.
    static func overflow(_ items: [TrayItem], maxItems: Int, keeping: Set<UUID> = []) -> Set<UUID> {
        let limit = max(maxItems, 1)
        guard items.count > limit else { return [] }
        let candidates = items.filter { !keeping.contains($0.id) }.sorted { $0.addedAt < $1.addedAt }
        return Set(candidates.prefix(items.count - limit).map(\.id))
    }

    /// Everything goes on quit (`.clearOnQuit`), and on the next launch if the app did not quit cleanly.
    static func clearsOnQuit(_ policy: TrayRetention) -> Bool { policy == .clearOnQuit }
}
