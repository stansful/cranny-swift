// CrannySystemActivities/Accessories/AccessoryTracker.swift — which reports are NEW connections (pure).
// Each source's first report is a baseline (launch, or the opt-in watcher starting): nothing announced.
// One device seen by two sources (Core Audio and IOBluetooth) is announced once.
import Foundation

nonisolated struct AccessoryTracker: Equatable, Sendable {
    nonisolated enum Source: Hashable, Sendable { case audio, hid, bluetooth }

    /// A second source reporting the same device within this window is the same connection.
    static let duplicateWindow: TimeInterval = 5

    private var known: [Source: Set<String>] = [:]
    private var announced: [String: Date] = [:]

    init() {}

    /// IDs in `ids` that were not connected at the previous report of `source`.
    mutating func newIDs(_ ids: Set<String>, from source: Source) -> Set<String> {
        defer { known[source] = ids }
        guard let previous = known[source] else { return [] }
        return ids.subtracting(previous)
    }

    /// The source stopped (the opt-in watcher turned off): its next report is a baseline again.
    mutating func forget(_ source: Source) { known[source] = nil }

    /// False when the same device (by normalized name) was announced less than `duplicateWindow` ago.
    mutating func shouldAnnounce(name: String, at now: Date) -> Bool {
        announced = announced.filter { now.timeIntervalSince($0.value) < Self.duplicateWindow }
        let key = AccessoryCatalog.normalizedName(name)
        guard !key.isEmpty else { return true }
        if announced[key] != nil { return false }
        announced[key] = now
        return true
    }
}
