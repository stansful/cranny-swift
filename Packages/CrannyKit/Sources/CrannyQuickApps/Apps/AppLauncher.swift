// CrannyQuickApps/Apps/AppLauncher.swift — opening apps and Finder/Shortcuts locations (R3 §6).
// Tests inject a recording fake: they never launch anything.
import AppKit
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.quickApps)

@MainActor protocol AppLaunching: AnyObject {
    /// Opens (or brings forward) the app at `url`.
    func open(_ url: URL) async throws
    /// Selects the app in a Finder window.
    func reveal(_ url: URL)
    /// Opens Shortcuts.app (the empty state of the shortcut picker).
    func openShortcutsApp()
}

@MainActor final class WorkspaceLauncher: AppLaunching {
    static let shortcutsAppID = "com.apple.shortcuts"

    func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    // The description names the app (user content, §9.3); the domain and code are safe to share.
                    let nsError = error as NSError
                    log.error("open \(url.lastPathComponent, privacy: .private) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public): \(nsError.localizedDescription, privacy: .private)")
                    continuation.resume(throwing: QuickAppsError.appLaunchFailed)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func openShortcutsApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.shortcutsAppID) else { return }
        Task { try? await open(url) }
    }
}
