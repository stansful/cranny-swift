// CrannyCore/Platform/AppIdentity.swift
// The name and icon of an app given its bundle identifier, for every place that shows apps (Settings ▸ Excluded apps
// and Permissions, Media's player rows and empty state, Quick Apps' names). One naming rule (`AppIdentity.name(of:)`):
// Finder's localized display name, or the bundle's file name where the bundle may not be read (an app left in
// Downloads: `ProtectedLocations`) or names nothing, never the bundle identifier. Launch Services and the bundle are
// read off the main actor (ARCHITECTURE.md §9.2), once per app until `refresh()`; views show nothing (or their own
// fallback) until the answer lands, and hide an app that is not installed or say so.
import AppKit
import Foundation
import Observation

/// An app as a list shows it.
public struct AppIdentity {
    /// What the lookup found.
    public nonisolated enum Presence: Sendable, Equatable {
        /// The lookup runs (a moment): show nothing rather than an identifier.
        case pending
        /// Launch Services knows the app.
        case installed
        /// No app with this identifier is installed.
        case notInstalled
    }

    /// Where an installed app is and what it is called: a lookup's answer, made off the main actor.
    public nonisolated struct Location: Sendable, Equatable {
        /// The bundle's location.
        public let url: URL
        /// `AppIdentity.name(of:)`.
        public let name: String
        /// Reading the bundle (its icon) cannot raise a privacy prompt.
        public let isSafeToRead: Bool

        /// A location.
        public init(url: URL, name: String, isSafeToRead: Bool) {
            self.url = url; self.name = name; self.isSafeToRead = isSafeToRead
        }
    }

    /// The bundle identifier it was looked up by (never shown).
    public let bundleID: String
    /// What the lookup found.
    public let presence: Presence
    /// Finder's name ("Music" / «Музыка», "Spotify"); nil while pending and when not installed. Never the bundle
    /// identifier.
    public let name: String?
    /// Where the app is, in any folder (opening it reads nothing); nil while pending and when not installed.
    public let url: URL?
    /// The app's icon (rendered lazily by Icon Services when drawn); nil until known, when not installed, and for an
    /// app in a protected folder (its icon would be read from the bundle).
    public let icon: NSImage?

    /// An identity.
    public init(bundleID: String, presence: Presence = .pending, name: String? = nil, url: URL? = nil, icon: NSImage? = nil) {
        self.bundleID = bundleID; self.presence = presence; self.name = name; self.url = url; self.icon = icon
    }

    /// Launch Services knows the app.
    public var isInstalled: Bool { presence == .installed }
    /// The lookup finished and found no app.
    public var isNotInstalled: Bool { presence == .notInstalled }
    /// The lookup still runs.
    public var isPending: Bool { presence == .pending }

    /// The name, or `fallback` while the app is unknown (pending or not installed).
    public func name(or fallback: String) -> String { name ?? fallback }

    // MARK: Naming (one rule for every surface)

    /// Finder's name for the app bundle at `url`: its localized display name where reading the bundle cannot raise
    /// a privacy prompt; elsewhere, and when the bundle names nothing, its file name without ".app"
    /// ("…/Downloads/Spotify.app" → "Spotify"). Never a bundle identifier. Reads the bundle: call it off the main
    /// actor. Tests inject `isSafeToRead` and `displayName`.
    public nonisolated static func name(of url: URL,
                                        isSafeToRead: (URL) -> Bool = { ProtectedLocations.isSafeToRead($0) },
                                        displayName: (URL) -> String = { AppIdentity.displayName(of: $0) }) -> String {
        let fileName = url.deletingPathExtension().lastPathComponent
        let read = isSafeToRead(url) ? displayName(url).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return read.isEmpty ? fileName : read
    }

    /// Finder's localized name of the app bundle at `url`, without the ".app" extension. Reads the bundle: call it
    /// off the main actor, and only where `ProtectedLocations.isSafeToRead` (or use `name(of:)`).
    public nonisolated static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// App identities for the session (`AppIdentityResolver.shared`), observable: a view that reads `identity(of:)`
/// updates when a lookup lands. `refresh()` looks every app seen so far up again (an app installed, moved or removed
/// meanwhile); an identity keeps what it shows until the answer differs.
@MainActor @Observable public final class AppIdentityResolver {
    /// The app-wide cache.
    public static let shared = AppIdentityResolver()

    private var known: [String: AppIdentity] = [:]
    /// The last answer per app (to keep an identity, and its icon, when a refresh finds the same).
    @ObservationIgnored private var found: [String: AppIdentity.Location?] = [:]
    /// Bumped whenever a lookup changes an answer (e.g. part of Settings' search-index signature).
    public private(set) var revision = 0
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private var again: Set<String> = []
    /// `@concurrent`: the lookup runs off the main actor, and awaiting it returns to the main actor.
    @ObservationIgnored private let locate: @concurrent @Sendable (String) async -> AppIdentity.Location?
    @ObservationIgnored private let iconForFile: @MainActor (URL) -> NSImage?

    /// `locate` answers for one bundle identifier (nil = not installed), off the main actor; `icon` gives the icon of
    /// a bundle that is safe to read. Tests inject both; the app uses `shared`.
    public init(locate: @escaping @concurrent @Sendable (String) async -> AppIdentity.Location? = { await AppIdentityResolver.locate($0) },
                icon: @escaping @MainActor (URL) -> NSImage? = { NSWorkspace.shared.icon(forFile: $0.path) }) {
        self.locate = locate
        iconForFile = icon
    }

    /// The app's identity. The first call per app starts the lookup and answers `.pending`; views reading this update
    /// when it lands. Never touches the disk on the main actor.
    public func identity(of bundleID: String) -> AppIdentity {
        if let identity = known[bundleID] { return identity }
        if !running.contains(bundleID) { lookUp(bundleID) }
        return AppIdentity(bundleID: bundleID)
    }

    /// Looks every app seen so far up again (Settings appeared, Cranny became active).
    public func refresh() {
        for bundleID in known.keys { lookUp(bundleID) }
    }

    /// A lookup still runs.
    public var isLookingUp: Bool { !running.isEmpty }

    private func lookUp(_ bundleID: String) {
        guard running.insert(bundleID).inserted else {
            again.insert(bundleID)                      // a refresh during a lookup asks once more when it lands
            return
        }
        let locate = self.locate
        Task { [weak self] in
            let location = await locate(bundleID)
            guard let self else { return }
            self.land(bundleID, location)
        }
    }

    private func land(_ bundleID: String, _ location: AppIdentity.Location?) {
        running.remove(bundleID)
        if found[bundleID] != .some(location) {                     // nothing known yet, or a different answer
            found[bundleID] = .some(location)
            known[bundleID] = location.map {
                AppIdentity(bundleID: bundleID, presence: .installed, name: $0.name, url: $0.url,
                            icon: $0.isSafeToRead ? iconForFile($0.url) : nil)
            } ?? AppIdentity(bundleID: bundleID, presence: .notInstalled)
            revision += 1
        }
        if again.remove(bundleID) != nil { lookUp(bundleID) }
    }

    // MARK: Lookups (off the main actor)

    /// Where the app is and its name (`AppIdentity.name(of:)`), or nil when it is not installed. Off the main actor.
    @concurrent public nonisolated static func locate(_ bundleID: String) async -> AppIdentity.Location? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let isSafe = ProtectedLocations.isSafeToRead(url)
        return AppIdentity.Location(url: url, name: AppIdentity.name(of: url, isSafeToRead: { _ in isSafe }), isSafeToRead: isSafe)
    }

    /// Where the app is, wherever that is (to launch it on the user's click: opening an app reads none of its files).
    /// Off the main actor.
    @concurrent public nonisolated static func applicationURL(for bundleID: String) async -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
