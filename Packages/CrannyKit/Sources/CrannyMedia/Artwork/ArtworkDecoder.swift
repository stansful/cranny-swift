// CrannyMedia/Artwork/ArtworkDecoder.swift — artwork bytes → a 512-px thumbnail + the album palette, off the
// main actor (ARCHITECTURE.md §6.5, D9: the palette is Core's `AmbientPalette.extract`, DESIGN.md §5.2).
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO

/// A decoded artwork and its palette. `CGImage` is immutable, so the pair is safe to share.
nonisolated struct DecodedArtwork: @unchecked Sendable {
    let image: CGImage
    let palette: AmbientPalette
}

nonisolated enum ArtworkDecoder {
    static let maxPixelSize = 512

    /// nil for bytes ImageIO cannot read. ≈ 0.3 ms for a 600-px JPEG (R2 §7).
    @concurrent static func decode(_ data: Data) async -> DecodedArtwork? {
        decodeNow(data)
    }

    /// Synchronous form (tests, sample artwork).
    static func decodeNow(_ data: Data) -> DecodedArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedArtwork(image: image, palette: AmbientPalette.extract(from: image))
    }
}

/// Which picture an artwork message carried: two messages for one track with the same fingerprint are the same
/// picture (a refresh, a restarted helper); a different one replaces it (placeholder art, then the real one).
nonisolated struct ArtworkFingerprint: Hashable, Sendable {
    let byteCount: Int
    let hash: Int

    init(_ data: Data) {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        byteCount = data.count
        hash = hasher.finalize()
    }

    /// Off the main actor: artwork can be a few megabytes.
    @concurrent static func of(_ data: Data) async -> ArtworkFingerprint { ArtworkFingerprint(data) }
}

/// Least-recently-used artwork by track key (16 entries, ARCHITECTURE.md §6.5). Pure value. Tracks of one picture (an
/// album's tracks usually carry identical bytes) can share one decoded image: `artwork(matching:)` finds it.
nonisolated struct ArtworkCache: Sendable {
    struct Entry: Sendable {
        let artwork: DecodedArtwork
        /// nil for artwork that did not come from a provider (the sample).
        let fingerprint: ArtworkFingerprint?
    }

    static let capacity = 16
    private var entries: [String: Entry] = [:]
    private var order: [String] = []          // least recently used first
    let capacity: Int

    init(capacity: Int = ArtworkCache.capacity) { self.capacity = max(capacity, 1) }

    var count: Int { entries.count }
    var keys: [String] { order }

    /// The cached artwork, marked as most recently used.
    mutating func value(for key: String) -> DecodedArtwork? { entry(for: key)?.artwork }

    /// The cached entry, marked as most recently used.
    mutating func entry(for key: String) -> Entry? {
        guard let hit = entries[key] else { return nil }
        touch(key)
        return hit
    }

    /// The decoded artwork of any entry made from the picture with `fingerprint`, without marking it as used; nil when
    /// none is cached.
    func artwork(matching fingerprint: ArtworkFingerprint) -> DecodedArtwork? {
        entries.values.first { $0.fingerprint == fingerprint }?.artwork
    }

    /// Adds or replaces the artwork of `key`.
    mutating func insert(_ artwork: DecodedArtwork, fingerprint: ArtworkFingerprint?, for key: String) {
        entries[key] = Entry(artwork: artwork, fingerprint: fingerprint)
        touch(key)
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// The service's artwork pipeline: fingerprint and decode off the main actor at utility priority (background work on
/// efficiency cores: the 600-ms artwork grace covers it), cache, and drop a decode that a newer picture for the same
/// track overtook. A picture already cached for another track (the next track of an album) is not decoded again: both
/// tracks share its image, so an album keeps one 1-MB decode in the cache instead of one per track.
@MainActor final class ArtworkStore {
    private var cache = ArtworkCache()
    private var requests = 0
    /// The newest request per track key.
    private var latest: [String: Int] = [:]

    func cached(_ key: String) -> DecodedArtwork? { cache.value(for: key) }

    /// Artwork that did not come from a provider (the sample).
    func seed(_ artwork: DecodedArtwork, for key: String) { cache.insert(artwork, fingerprint: nil, for: key) }

    /// Calls `deliver` with the picture for `key` once it is decoded (or at once from the cache when the same
    /// picture is cached already), unless a newer picture for `key` arrived meanwhile. Unreadable data is ignored.
    func receive(key: String, data: Data, deliver: @escaping @MainActor (DecodedArtwork) -> Void) {
        requests += 1
        let request = requests
        latest[key] = request
        Task(priority: .utility) { [weak self] in
            let fingerprint = await ArtworkFingerprint.of(data)
            guard let self, self.latest[key] == request else { return }
            if let cached = self.cache.entry(for: key), cached.fingerprint == fingerprint {
                self.latest[key] = nil
                deliver(cached.artwork)
                return
            }
            if let shared = self.cache.artwork(matching: fingerprint) {
                self.latest[key] = nil
                self.cache.insert(shared, fingerprint: fingerprint, for: key)
                deliver(shared)
                return
            }
            let decoded = await ArtworkDecoder.decode(data)
            guard self.latest[key] == request else { return }
            self.latest[key] = nil
            guard let decoded else { return }
            self.cache.insert(decoded, fingerprint: fingerprint, for: key)
            deliver(decoded)
        }
    }
}
