// CrannyQuickApps/Apps/AppCatalog.swift — which quick apps are installed, and their icons (cached).
//
// Resolution runs at launch, whenever `QuickAppsSettings.apps` changes and when an app the catalog could not
// find is launched (it was just installed). Icons are rendered off the main actor once per size and cached.
import CoreGraphics
import Foundation
import Observation

@MainActor @Observable final class AppCatalog {
    /// Installed quick apps, by bundle identifier.
    private(set) var apps: [String: ResolvedApp] = [:]
    /// Bundle identifiers that were looked up and are not installed.
    private(set) var missing: Set<String> = []
    /// False until the first resolution finished: the launcher shows nothing rather than a false "empty" state.
    private(set) var hasResolved = false

    @ObservationIgnored let resolver: any AppResolving
    @ObservationIgnored private var icons: [IconKey: CGImage] = [:]
    @ObservationIgnored private var generation = 0

    private struct IconKey: Hashable { let url: URL; let pixels: Int }
    /// Icons kept in memory (a launcher has a few dozen at most; Settings adds a smaller size).
    private static let iconLimit = 96

    init(resolver: any AppResolving) { self.resolver = resolver }

    func app(_ bundleID: String) -> ResolvedApp? { apps[bundleID] }
    func isMissing(_ bundleID: String) -> Bool { missing.contains(bundleID) }

    /// Looks up every bundle id (in parallel off the main actor); a newer call supersedes an older one.
    func refresh(_ bundleIDs: [String]) async {
        generation += 1
        let mine = generation
        let resolver = resolver
        let unique = Array(Set(bundleIDs))
        let known = apps
        let found = await withTaskGroup(of: (String, ResolvedApp?).self) { group in
            for id in unique {
                group.addTask {
                    if let app = await resolver.resolve(id) { return (id, app) }
                    // An app added from a drop or the open panel that LaunchServices has not registered yet (a fresh
                    // download): keep it while its bundle is still where it was found.
                    if let previous = known[id], let app = await resolver.app(at: previous.url), app.bundleID == id {
                        return (id, app)
                    }
                    return (id, nil)
                }
            }
            var result: [(String, ResolvedApp?)] = []
            for await pair in group { result.append(pair) }
            return result
        }
        guard mine == generation else { return }
        var apps: [String: ResolvedApp] = [:]
        var missing = Set<String>()
        for (id, app) in found {
            if let app { apps[id] = app } else { missing.insert(id) }
        }
        if apps != self.apps { self.apps = apps }
        if missing != self.missing { self.missing = missing }
        if !hasResolved { hasResolved = true }
    }

    /// The apps among `urls` (application bundles with a bundle identifier), in order, without repeats.
    func apps(at urls: [URL]) async -> [ResolvedApp] {
        var seen = Set<String>()
        var result: [ResolvedApp] = []
        for url in urls {
            guard let app = await resolver.app(at: url), seen.insert(app.bundleID).inserted else { continue }
            result.append(app)
        }
        return result
    }

    /// Records an app found through a drop or the open panel, so its tile appears before the next refresh.
    func insert(_ app: ResolvedApp) {
        apps[app.bundleID] = app
        missing.remove(app.bundleID)
    }

    /// Previews, snapshots and QA: a resolved catalog without lookups.
    func seed(_ apps: [ResolvedApp], missing: Set<String> = []) {
        self.apps = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        self.missing = missing
        hasResolved = true
    }

    /// The icon of the app at `url`, `pixelSize` square; cached.
    func icon(at url: URL, pixelSize: Int) async -> CGImage? {
        let key = IconKey(url: url, pixels: pixelSize)
        if let cached = icons[key] { return cached }
        guard let image = await resolver.icon(at: url, pixelSize: pixelSize) else { return nil }
        if icons.count >= Self.iconLimit { icons.removeAll(keepingCapacity: true) }
        icons[key] = image
        return image
    }

    /// A cached icon (synchronous, for the first frame of a tile that was on screen before).
    func cachedIcon(at url: URL, pixelSize: Int) -> CGImage? { icons[IconKey(url: url, pixels: pixelSize)] }
}
