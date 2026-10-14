// CrannyQuickApps/Apps/RunningApps.swift — the set of running apps, as a pure reducer (tested).
import Foundation

/// Running instances per bundle identifier: an app with two instances stays "running" until both quit.
nonisolated struct RunningApps: Equatable, Sendable {
    private(set) var counts: [String: Int] = [:]

    init(_ bundleIDs: [String] = []) {
        for id in bundleIDs { counts[id, default: 0] += 1 }
    }

    func contains(_ bundleID: String) -> Bool { (counts[bundleID] ?? 0) > 0 }

    mutating func launched(_ bundleID: String) { counts[bundleID, default: 0] += 1 }

    mutating func terminated(_ bundleID: String) {
        guard let n = counts[bundleID] else { return }
        counts[bundleID] = n > 1 ? n - 1 : nil
    }
}
