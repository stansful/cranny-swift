// CrannyCore/Platform/AppIdentity.swift
// The name and icon of an app given its bundle identifier, for every list that shows apps (Settings ▸ Excluded apps
// and Permissions, Media's player rows and empty state). The Launch Services lookup and the bundle's display name are
// read off the main actor (ARCHITECTURE.md §9.2), once per app and session; views show a fallback until they arrive.
// Apps in protected folders (`ProtectedLocations`: an app left in Downloads) keep their identifier and no icon, so
// listing them never raises a Files & Folders prompt.
import AppKit
import Foundation
import Observation

/// An app as a list shows it.
public struct AppIdentity {
    /// The bundle identifier it was looked up by.
    public let bundleID: String
    /// Where the app is; nil while the lookup runs, when it is not installed or when it sits in a protected folder.
    public let url: URL?
    /// The localized display name without ".app", or the bundle identifier until (or unless) it is known.
    public let name: String
    /// The app's icon (rendered lazily by Icon Services when drawn); nil until known.
    public let icon: NSImage?
    /// The lookup has finished (false while it runs): with `isResolved` false, the app is not installed (or sits in
    /// a protected folder).
    public let isLookedUp: Bool

    /// A resolved app: its location is known (and safe to read).
    public var isResolved: Bool { url != nil }

    /// An identity; `name` defaults to the bundle identifier.
    public init(bundleID: String, url: URL? = nil, name: String? = nil, icon: NSImage? = nil, isLookedUp: Bool = false) {
        self.bundleID = bundleID; self.url = url; self.name = name ?? bundleID; self.icon = icon
        self.isLookedUp = isLookedUp
    }

    /// Finder's localized name of the app bundle at `url`, without the ".app" extension. Reads the bundle: call it
    /// off the main actor.
    public nonisolated static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Resolved app identities for the session (`AppIdentityResolver.shared`), observable: a view that reads
/// `identity(of:)` updates when the lookup finishes.
@MainActor @Observable public final class AppIdentityResolver {
    /// The app-wide cache.
    public static let shared = AppIdentityResolver()

    private var resolved: [String: AppIdentity] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    /// A resolver with an empty cache (tests); the app uses `shared`.
    public init() {}

    /// How many apps have been looked up (resolved or not found).
    public var resolvedCount: Int { resolved.count }

    /// The app's identity. The first call per app starts the lookup and returns the identifier with no icon; views
    /// reading this update when it finishes. Never touches the disk on the main actor.
    public func identity(of bundleID: String) -> AppIdentity {
        if let known = resolved[bundleID] { return known }
        if pending.insert(bundleID).inserted {
            Task { [weak self] in
                let location = await Self.locate(bundleID)
                let icon = location.map { NSWorkspace.shared.icon(forFile: $0.url.path) }   // drawn lazily
                self?.resolved[bundleID] = AppIdentity(bundleID: bundleID, url: location?.url, name: location?.name, icon: icon,
                                                       isLookedUp: true)
                self?.pending.remove(bundleID)
            }
        }
        return AppIdentity(bundleID: bundleID)
    }

    /// Where the app is and its display name, or nil when it is unknown or in a protected folder. Off the main actor.
    @concurrent public nonisolated static func locate(_ bundleID: String) async -> (url: URL, name: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              ProtectedLocations.isSafeToRead(url) else { return nil }
        return (url, AppIdentity.displayName(of: url))
    }

    /// Where the app is, wherever that is (to launch it on the user's click: opening an app reads none of its files).
    /// Off the main actor.
    @concurrent public nonisolated static func applicationURL(for bundleID: String) async -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
