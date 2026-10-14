// CrannyMedia/Service/MediaFilter.swift — which sessions reach the UI (Settings ▸ Media "Ignore apps" and
// "Show browser media", ARCHITECTURE.md §6.5). Pure.
import CrannyCore
import Foundation

nonisolated struct MediaFilter: Equatable, Sendable {
    var ignoredBundleIDs: Set<String>
    var showsBrowserMedia: Bool

    init(ignoredBundleIDs: some Sequence<String> = [], showsBrowserMedia: Bool = true) {
        self.ignoredBundleIDs = Set(ignoredBundleIDs.map { $0.lowercased() })
        self.showsBrowserMedia = showsBrowserMedia
    }

    /// The snapshot to publish, or nil when its player (or the app hosting it) is filtered out.
    func apply(_ nowPlaying: NowPlaying?) -> NowPlaying? {
        guard let nowPlaying else { return nil }
        let owners = [nowPlaying.bundleID, nowPlaying.parentBundleID].compactMap { $0?.lowercased() }
        if owners.contains(where: ignoredBundleIDs.contains) { return nil }
        if !showsBrowserMedia, owners.contains(where: BrowserCatalog.isBrowser) { return nil }
        return nowPlaying
    }
}

/// Web browsers (and their helper processes) whose sessions "Show browser media" hides.
nonisolated enum BrowserCatalog {
    /// Exact bundle identifiers, lowercased.
    static let bundleIDs: Set<String> = [
        "com.apple.safari", "com.apple.safaritechnologypreview", "com.apple.webkit.gpu",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.brave.browser", "com.brave.browser.beta", "company.thebrowser.browser", "company.thebrowser.dia",
        "com.operasoftware.opera", "com.operasoftware.operagx", "com.vivaldi.vivaldi", "org.chromium.chromium",
        "ru.yandex.desktop.yandex-browser", "com.kagi.kagimacos", "app.zen-browser.zen", "com.sigmaos.sigmaos.macos",
    ]
    /// Families with many channels and helper processes ("com.google.Chrome.canary", "….helper").
    static let prefixes = ["com.google.chrome", "com.microsoft.edgemac", "com.brave.browser", "org.chromium."]

    static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return bundleIDs.contains(id) || prefixes.contains { id.hasPrefix($0) }
    }
}
