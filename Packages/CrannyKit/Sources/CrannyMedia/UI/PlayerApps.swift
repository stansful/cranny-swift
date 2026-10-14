// CrannyMedia/UI/PlayerApps.swift — names, icons and launching of player apps by bundle id (the artwork click
// "Open in Music", the empty state's last source, Settings ▸ Media's Automation rows and Ignore apps). Names, icons and
// locations come from CrannyCore's `AppIdentityResolver`: looked up off the main actor, observable (a view updates when
// the lookup lands), Finder's name (the file name for a player in a protected folder: "Spotify", never "client" or the
// bundle identifier) and never an icon read from a protected folder. Launching happens only on a user's click and never
// starts playback.
import AppKit
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@MainActor enum PlayerApps {
    private static var resolver: AppIdentityResolver { .shared }

    /// What the lookup knows about the player (pending, installed with its name, or not installed).
    static func identity(_ bundleID: String) -> AppIdentity { resolver.identity(of: bundleID) }

    /// The player's name: Finder's once the lookup found it, else `fallback` (the name the player gave its session);
    /// nil while neither is known. Never derived from the bundle identifier.
    static func name(for bundleID: String, fallback: String? = nil) -> String? {
        identity(bundleID).name ?? fallback
    }

    /// The app's icon, nil until known (and for a player in a protected folder).
    static func icon(for bundleID: String) -> NSImage? { identity(bundleID).icon }

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
