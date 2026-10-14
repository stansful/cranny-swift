// CrannyAppShell/MenuBar/UpdateAlert.swift — the result of "Check for Updates…" from the menu bar extra: a
// standard alert with the app icon (nothing custom), shown after the check finishes. "View Release" opens the
// GitHub release page; Cranny never downloads or installs anything (ARCHITECTURE.md §7.11). Activation goes
// back to the app that was in front, unless the user opened the release page.
import AppKit
import CrannyCore
import Foundation

enum UpdateAlert {
    /// What the alert says for a finished check (nil while idle or checking).
    struct Content: Equatable {
        var title: String
        var message: String
        var primaryButton: String
        var secondaryButton: String?
        /// Opened when the primary button is chosen.
        var link: URL?
    }

    static func content(for state: UpdateState, currentVersion: String) -> Content? {
        switch state {
        case .idle, .checking:
            return nil
        case .available(let version, let url):
            return Content(
                title: String(localized: "Cranny \(version) is available", bundle: .module,
                              comment: "Update alert: title; the argument is the new version, e.g. 0.2.0"),
                message: String(localized: "You have version \(currentVersion). The release page has the download and the release notes.",
                                bundle: .module, comment: "Update alert: message under the title; the argument is the running version"),
                primaryButton: String(localized: "View Release", bundle: .module, comment: "Update alert: button that opens the GitHub release page"),
                secondaryButton: String(localized: "Later", bundle: .module, comment: "Update alert: button that closes the alert"),
                link: url)
        case .upToDate:
            return Content(
                title: String(localized: "Cranny is up to date", bundle: .module, comment: "Update alert: title when no newer release exists"),
                message: String(localized: "Version \(currentVersion) is the newest version.", bundle: .module,
                                comment: "Update alert: message when up to date; the argument is the running version"),
                primaryButton: okTitle, secondaryButton: nil, link: nil)
        case .failed(let reason):
            return Content(
                title: String(localized: "Couldn't check for updates", bundle: .module, comment: "Update alert: title when the check failed"),
                message: reason, primaryButton: okTitle, secondaryButton: nil, link: nil)
        }
    }

    /// Shows the alert for `state` (in response to the user's menu click, so activating is fine).
    static func present(_ state: UpdateState, currentVersion: String,
                        open: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        guard let content = content(for: state, currentVersion: currentVersion) else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        if case .failed = state { alert.alertStyle = .warning } else { alert.alertStyle = .informational }
        alert.messageText = content.title
        alert.informativeText = content.message
        alert.addButton(withTitle: content.primaryButton)
        if let secondary = content.secondaryButton { alert.addButton(withTitle: secondary) }
        NSApp.activate()
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let link = content.link {
            open(link)
        } else if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier, !previous.isTerminated {
            previous.activate()
        }
    }

    private static var okTitle: String { String(localized: "OK", bundle: .module, comment: "Update alert: button that closes the alert") }
}
