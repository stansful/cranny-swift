// CrannyMedia/UI/PlayerApps.swift — names, icons and launching of player apps by bundle id (the artwork click
// "Open in Music", the empty state's last source, Settings ▸ Media ▸ Ignore apps). LaunchServices lookups are
// cached per bundle id; launching happens only on a user's click and never starts playback.
import AppKit
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@MainActor enum PlayerApps {
    private static var urls: [String: URL?] = [:]
    private static var icons: [String: NSImage] = [:]

    static func url(for bundleID: String) -> URL? {
        if let cached = urls[bundleID] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        urls[bundleID] = url
        return url
    }

    /// The app's display name, else the last component of its bundle id.
    static func name(for bundleID: String, fallback: String? = nil) -> String {
        if let url = url(for: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return fallback ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Brings the player to the front (launching it if needed). Never sends a transport command.
    static func open(_ bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("media: cannot open player: \(error.localizedDescription, privacy: .private)") }
        }
    }

    static let music = "com.apple.Music"
}
