// CrannyTray/Thumbnails/ThumbnailCache.swift — Quick Look thumbnails for tiles (DESIGN.md §8.1: 44-pt thumbnail,
// r 8), generated off the main actor by `QLThumbnailGenerator` and kept in a small LRU (ARCHITECTURE.md §7.8, §9.2:
// decode off-main, cache thumbnails). Tiles draw a cached one on their first frame (`cached`) and ask for a missing
// one on appear (`.task(id:)`); nothing is generated for hidden tiles. Items that leave the Tray leave the cache.
import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// A generated thumbnail. `isIcon` = Quick Look had no preview, only the file type's icon (drawn unclipped).
nonisolated struct TrayThumbnail: Sendable {
    let image: CGImage
    let isIcon: Bool
}

/// Least-recently-used storage (pure, tested).
nonisolated struct LRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = max(capacity, 1) }

    var count: Int { values.count }

    mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        touch(key)
        while order.count > capacity { values[order.removeFirst()] = nil }
    }

    mutating func removeAll() { values = [:]; order = [] }

    /// Drops every entry whose key matches.
    mutating func removeValues(where shouldRemove: (Key) -> Bool) {
        order.removeAll(where: shouldRemove)
        values = values.filter { !shouldRemove($0.key) }
    }

    private mutating func touch(_ key: Key) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }
}

@MainActor final class ThumbnailCache {
    /// A file at one pixel size (tiles and the Files widget, 1× and 2× displays, are cached apart).
    nonisolated struct Key: Hashable, Sendable {
        let path: String
        let pixels: Int

        init(_ url: URL, pointSize: CGFloat, scale: CGFloat) {
            path = url.path
            pixels = Int(pointSize * scale)
        }
    }

    private var cache = LRUCache<Key, TrayThumbnail>(capacity: 160)
    private var inFlight: [Key: Task<TrayThumbnail?, Never>] = [:]

    /// The thumbnail of `url` at `pointSize` × `scale`, from the cache or freshly generated.
    func thumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) async -> TrayThumbnail? {
        let key = Key(url, pointSize: pointSize, scale: scale)
        if let hit = cache.value(for: key) { return hit }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await Self.generate(url, size: CGSize(width: pointSize, height: pointSize), scale: scale) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache.insert(result, for: key) }
        return result
    }

    /// A thumbnail that is already cached (a tile's first frame, the drag image), without generating one.
    func cached(for url: URL, pointSize: CGFloat, scale: CGFloat) -> TrayThumbnail? {
        cache.value(for: Key(url, pointSize: pointSize, scale: scale))
    }

    /// Forgets the thumbnails of files that left the Tray, at every size.
    func forget(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        cache.removeValues { paths.contains($0.path) }
    }

    /// Forget everything (memory pressure is handled by the small capacity; this is for Clear).
    func removeAll() { cache.removeAll() }

    @concurrent private static func generate(_ url: URL, size: CGSize, scale: CGFloat) async -> TrayThumbnail? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let representation else { continuation.resume(returning: nil); return }
                continuation.resume(returning: TrayThumbnail(image: representation.cgImage, isIcon: representation.type == .icon))
            }
        }
    }
}
