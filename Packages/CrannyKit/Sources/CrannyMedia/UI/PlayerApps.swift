// CrannyMedia/UI/PlayerApps.swift — names, icons and launching of player apps by bundle id (the artwork click
// "Open in Music", the empty state's last source, Settings ▸ Media ▸ Ignore apps). Names, icons and locations come
// from CrannyCore's `AppIdentityResolver`: looked up off the main actor once per app, observable (a view updates when
// the lookup finishes) and never read from a protected folder. Launching happens only on a user's click and never
// starts playback.
import AppKit
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@MainActor enum PlayerApps {
    private static var resolver: AppIdentityResolver { .shared }

    /// Where the player is: nil while the lookup runs, when it is not installed or in a protected folder.
    static func url(for bundleID: String) -> URL? { resolver.identity(of: bundleID).url }

    /// The app's display name; until it is known (or if it is not installed), `fallback` or the last component of
    /// its bundle id.
    static func name(for bundleID: String, fallback: String? = nil) -> String {
        let identity = resolver.identity(of: bundleID)
        if identity.isResolved { return identity.name }
        return fallback ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    /// The app's icon, nil until known.
    static func icon(for bundleID: String) -> NSImage? { resolver.identity(of: bundleID).icon }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Brings the player to the front (launching it if needed). Never sends a transport command. The app is located
    /// off the main actor; opening it reads none of its files, so a player in any folder opens.
    static func open(_ bundleID: String) {
        Task {
            guard let url = await AppIdentityResolver.applicationURL(for: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { log.error("media: cannot open player: \(error.localizedDescription, privacy: .private)") }
            }
        }
    }

    static let music = "com.apple.Music"
}
