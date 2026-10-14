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

/// Least-recently-used artwork by track key (16 entries, ARCHITECTURE.md §6.5). Pure value.
nonisolated struct ArtworkCache: Sendable {
    static let capacity = 16
    private var entries: [String: DecodedArtwork] = [:]
    private var order: [String] = []          // least recently used first
    let capacity: Int

    init(capacity: Int = ArtworkCache.capacity) { self.capacity = max(capacity, 1) }

    var count: Int { entries.count }
    var keys: [String] { order }

    /// The cached artwork, marked as most recently used.
    mutating func value(for key: String) -> DecodedArtwork? {
        guard let hit = entries[key] else { return nil }
        touch(key)
        return hit
    }

    mutating func insert(_ artwork: DecodedArtwork, for key: String) {
        entries[key] = artwork
        touch(key)
        while order.count > capacity { entries[order.removeFirst()] = nil }
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
