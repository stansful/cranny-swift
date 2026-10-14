// CrannySettingsUI/Panes/AutomationApps.swift — the app an Automation row of Settings ▸ Permissions is for, named the
// way Finder names it and never by its bundle identifier (ARCHITECTURE §10.20 issue 11). Launch Services locates the
// app and its display name is read off the main actor (§9.2). A bundle in a protected folder (an app left in
// Downloads) is named from its file name without being read, so the pane raises no Files & Folders prompt. An app that
// is not installed gets no row: there is nothing to allow, and System Settings lists no such app either. Apps are
// looked up again whenever the pane appears or Cranny becomes active, so installing or removing a player shows
// without a relaunch; a row keeps what it shows until the answer differs.
import AppKit
import CrannyCore
import Foundation
import Observation

/// What Settings knows about the app of an Automation row.
nonisolated enum AutomationApp: Equatable, Sendable {
    /// The lookup runs; the row waits for it (a moment) instead of showing an identifier.
    case pending
    /// Installed, with Finder's localized name ("Music" / «Музыка», "Spotify").
    case installed(name: String)
    /// No app with this identifier is installed: the row is hidden.
    case notInstalled

    /// The name to show; nil while there is no row.
    var name: String? {
        if case .installed(let name) = self { return name }
        return nil
    }

    /// The app at `url` (nil: not installed). The bundle's display name is read only where that is safe; elsewhere,
    /// and when the bundle names nothing, the file name stands in ("Spotify.app" → "Spotify"). Never the bundle
    /// identifier. Reads the bundle: call it off the main actor.
    static func resolve(_ url: URL?,
                        isSafeToRead: (URL) -> Bool = { ProtectedLocations.isSafeToRead($0) },
                        displayName: (URL) -> String = { AppIdentity.displayName(of: $0) }) -> AutomationApp {
        guard let url else { return .notInstalled }
        let fileName = url.deletingPathExtension().lastPathComponent
        let read = isSafeToRead(url) ? displayName(url).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return .installed(name: read.isEmpty ? fileName : read)
    }

    /// Launch Services, then the bundle's display name, off the main actor.
    @concurrent static func lookUp(_ bundleID: String) async -> AutomationApp {
        resolve(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID))
    }
}

/// The Automation apps of this session, observable: the pane and the search index read `app(_:)` and update when a
/// lookup lands.
@Observable final class AutomationApps {
    /// The app-wide cache (the pane and the search index share it).
    static let shared = AutomationApps()

    private var known: [String: AutomationApp] = [:]
    /// Bumped whenever a lookup changes an answer (part of the search index's signature).
    private(set) var revision = 0
    @ObservationIgnored private var running: Set<String> = []
    @ObservationIgnored private let locate: @Sendable (String) async -> AutomationApp

    /// `locate` answers for one bundle identifier off the main actor (tests inject one).
    init(locate: @escaping @Sendable (String) async -> AutomationApp = { await AutomationApp.lookUp($0) }) {
        self.locate = locate
    }

    /// The app of `bundleID`. The first call starts the lookup and answers `.pending`; views reading this update when
    /// it finishes.
    func app(_ bundleID: String) -> AutomationApp {
        if let app = known[bundleID] { return app }
        lookUp(bundleID)
        return .pending
    }

    /// Looks every known app up again (the pane appeared, Cranny became active: a player may have been installed or
    /// removed meanwhile).
    func refresh() {
        for bundleID in known.keys { lookUp(bundleID) }
    }

    /// A lookup is still running.
    var isLookingUp: Bool { !running.isEmpty }

    private func lookUp(_ bundleID: String) {
        guard running.insert(bundleID).inserted else { return }
        let locate = self.locate
        Task { [weak self] in
            let app = await locate(bundleID)
            guard let self else { return }
            self.running.remove(bundleID)
            guard self.known[bundleID] != app else { return }
            self.known[bundleID] = app
            self.revision += 1
        }
    }
}
