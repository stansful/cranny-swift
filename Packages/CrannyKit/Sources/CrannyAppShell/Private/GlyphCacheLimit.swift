// CrannyAppShell/Private/GlyphCacheLimit.swift — bounds CoreGraphics' glyph cache through PRIVATE CoreGraphics calls
// (ARCHITECTURE.md §7.12, §9.2 "Energy pass" ▸ Memory).
//
// Why: CoreGraphics keeps each glyph it rasterizes in the process's font cache, one "strike" per font size and
// transform. A `.numericText` content transition (the calendar's "+N more" on every open, event countdowns, HUD and
// battery percentages) draws its glyphs at a new scale in every frame, so each transition adds strikes that are never
// drawn again. The cache's limit counts glyph pixels only (16,000,000 by default), while a strike costs 10–30 times
// its count in malloc: a test window rolling one short number grew by ≈ 375 MB before the default limit held it
// (≈ 30 MB with this one), and Cranny grew 1.5–3 MB with every open of Home with a calendar, for well over a hundred
// opens. Cranny's own text fills ≈ 0.15–0.4 MB of the count; a glyph that left the cache is rasterized again the same
// way (same pixels).
//
// Resolved with `dlsym` (never linked; on macOS 27 `CGFontCacheGetMaxSize` and `CGFontCacheSetMaxSize` read and write
// the limit of the cache that `CGFontCacheGetLocalCache` returns); without them the default limit stays and one info
// line says so. `-CrannyDisableGlyphCacheLimit YES` (also Release) keeps the default for A/B memory runs.
import CoreGraphics
import CrannyCore
import Foundation
import os

private let log = Log.logger(.app)

enum GlyphCacheLimit {
    /// The process's font cache limit in CoreGraphics' own accounting (glyph pixels; the default is 16,000,000).
    static let maxSize = 1_000_000

    /// Lowers the limit once, before the first window draws. Never raises a smaller limit set elsewhere.
    static func apply(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "CrannyDisableGlyphCacheLimit") else {
            log.info("glyph cache: CoreGraphics' default limit kept (-CrannyDisableGlyphCacheLimit)")
            return
        }
        guard let cache = FontCache.local else {
            log.info("glyph cache: CGFontCache calls unavailable, CoreGraphics' default limit kept")
            return
        }
        let current = cache.maxSize
        guard current > maxSize else { return }
        cache.maxSize = maxSize
        log.info("glyph cache limit \(current, privacy: .public) → \(maxSize, privacy: .public)")
    }

    /// The limit now; nil where the calls are missing (tests).
    static var currentLimit: Int? { FontCache.local?.maxSize }

    /// The process's CoreGraphics font cache, reached through the private calls.
    private struct FontCache {
        private typealias GetLocalCache = @convention(c) () -> OpaquePointer?
        private typealias GetMaxSize = @convention(c) (OpaquePointer) -> Int
        private typealias SetMaxSize = @convention(c) (OpaquePointer, Int) -> Void

        private let cache: OpaquePointer
        private let getMax: GetMaxSize
        private let setMax: SetMaxSize

        /// nil when CoreGraphics lacks a call or has no local cache.
        static var local: FontCache? {
            guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
                  let getLocal = dlsym(handle, "CGFontCacheGetLocalCache"),
                  let getMax = dlsym(handle, "CGFontCacheGetMaxSize"),
                  let setMax = dlsym(handle, "CGFontCacheSetMaxSize"),
                  let cache = unsafeBitCast(getLocal, to: GetLocalCache.self)() else { return nil }
            return FontCache(cache: cache, getMax: unsafeBitCast(getMax, to: GetMaxSize.self),
                             setMax: unsafeBitCast(setMax, to: SetMaxSize.self))
        }

        var maxSize: Int {
            get { getMax(cache) }
            nonmutating set { setMax(cache, newValue) }
        }
    }
}
