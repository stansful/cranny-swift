// CrannyQuickApps/Model/LauncherOrder.swift — one tile order across the two persisted lists (pure, tested).
import Foundation

/// Apps and shortcuts live in two settings keys; `QuickAppsSettings.order` interleaves them once the user
/// reorders. These functions are the only place that combines the three.
nonisolated enum LauncherOrder {
    /// Every tile, in display order: the ids listed in `order` (unknown and repeated ids skipped), then the
    /// apps not listed there, then the shortcuts not listed there, each in its list's order.
    static func arrange(apps: [AppEntry], shortcuts: [ShortcutEntry], order: [String]) -> [TileID] {
        let all = apps.map { TileID.app($0.bundleID) } + shortcuts.map { TileID.shortcut($0.id) }
        let known = Set(all)
        var seen = Set<TileID>()
        var result: [TileID] = []
        result.reserveCapacity(all.count)
        for raw in order {
            guard let id = TileID(rawValue: raw), known.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in all where seen.insert(id).inserted { result.append(id) }
        return result
    }

    /// `arrangement` with `id` moved to position `index` among the VISIBLE tiles (`isVisible`). Hidden tiles
    /// (apps that are not installed) keep their absolute positions, so they come back where they were.
    static func move(_ id: TileID, toVisibleIndex index: Int, in arrangement: [TileID],
                     isVisible: (TileID) -> Bool) -> [TileID] {
        var visible = arrangement.filter(isVisible)
        guard let from = visible.firstIndex(of: id) else { return arrangement }
        visible.remove(at: from)
        visible.insert(id, at: min(max(index, 0), visible.count))
        var next = visible.makeIterator()
        return arrangement.map { isVisible($0) ? (next.next() ?? $0) : $0 }
    }
}
