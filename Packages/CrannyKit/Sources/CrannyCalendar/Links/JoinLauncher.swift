// CrannyCalendar/Links/JoinLauncher.swift — Join opens the meeting in the service's own app when it is
// installed and the user allows it (`CalendarSettings.joinsInApp`), otherwise in the browser (ARCHITECTURE.md
// §7.4; R3 §4: `urlForApplication(toOpen:)` resolves `zoommtg://` to zoom.us when Zoom is installed).
// Opening goes through `URLOpening`, so tests never launch anything.
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.calendar)

/// The system side of opening URLs (NSWorkspace in the app, a recorder in tests).
@MainActor protocol URLOpening: AnyObject {
    /// The app that would open `url`, if any (never launches it).
    func applicationURL(toOpen url: URL) -> URL?
    /// Opens `url`; returns false when nothing could open it.
    @discardableResult func open(_ url: URL) -> Bool
    /// Launches (or brings forward) an app by bundle identifier; false when it is not installed.
    @discardableResult func openApplication(bundleIdentifier: String) -> Bool
}

@MainActor final class WorkspaceURLOpener: URLOpening {
    func applicationURL(toOpen url: URL) -> URL? { NSWorkspace.shared.urlForApplication(toOpen: url) }
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func openApplication(bundleIdentifier: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

/// Opens nothing (samples and previews).
@MainActor final class InertURLOpener: URLOpening {
    func applicationURL(toOpen url: URL) -> URL? { nil }
    func open(_ url: URL) -> Bool { false }
    func openApplication(bundleIdentifier: String) -> Bool { false }
}

/// Where a Join went.
nonisolated enum JoinOutcome: Equatable, Sendable {
    case app(URL)
    case browser(URL)
    case failed
}

@MainActor final class JoinLauncher {
    private let opener: any URLOpening
    private let joinsInApp: @MainActor () -> Bool

    init(opener: any URLOpening, joinsInApp: @escaping @MainActor () -> Bool) {
        self.opener = opener
        self.joinsInApp = joinsInApp
    }

    /// Opens the meeting. Never called from tests with a real opener.
    @discardableResult func join(_ link: MeetingLink) -> JoinOutcome {
        let outcome = Self.plan(link, joinsInApp: joinsInApp(), hasApp: { [opener] in opener.applicationURL(toOpen: $0) != nil })
        switch outcome {
        case .app(let url), .browser(let url):
            guard opener.open(url) else {
                log.error("join: nothing opened the \(link.service.rawValue, privacy: .public) link")
                return .failed
            }
            log.info("join: \(link.service.rawValue, privacy: .public) via \(url.scheme ?? "-", privacy: .public)")
            return outcome
        case .failed:
            log.error("join: no usable URL for \(link.service.rawValue, privacy: .public)")
            return .failed
        }
    }

    /// The decision, as a pure function: the native URL when wanted and an app handles it, else the web URL.
    nonisolated static func plan(_ link: MeetingLink, joinsInApp: Bool, hasApp: (URL) -> Bool) -> JoinOutcome {
        if joinsInApp, let native = NativeJoinURL.native(for: link), hasApp(native) {
            return .app(native)
        }
        if let web = NativeJoinURL.web(for: link) {
            return .browser(web)
        }
        // A native-only link (zoommtg:// without a web form): it still opens if its app exists.
        return hasApp(link.url) ? .app(link.url) : .failed
    }
}

/// Conversions between a service's web link and its app's URL scheme.
nonisolated enum NativeJoinURL {
    /// The URL the service's app opens directly, or nil when the service has no app scheme we know.
    static func native(for link: MeetingLink) -> URL? {
        let scheme = link.url.scheme?.lowercased()
        switch link.service {
        case .zoom:
            if scheme == "zoommtg" || scheme == "zoomus" { return link.url }
            return zoomNative(link.url)
        case .teams:
            if scheme == "msteams" { return link.url }
            return teamsNative(link.url)
        default:
            return nil
        }
    }

    /// The http(s) form of the link (the link itself when it already is one).
    static func web(for link: MeetingLink) -> URL? {
        switch link.url.scheme?.lowercased() {
        case "http", "https": return link.url
        case "zoommtg", "zoomus": return zoomWeb(link.url)
        case "msteams": return teamsWeb(link.url)
        default: return nil
        }
    }

    /// `https://acme.zoom.us/j/123?pwd=abc` → `zoommtg://acme.zoom.us/join?action=join&confno=123&pwd=abc`.
    private static func zoomNative(_ url: URL) -> URL? {
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "j", let host = url.host, parts[1].allSatisfy(\.isNumber) else { return nil }
        var c = URLComponents()
        c.scheme = "zoommtg"
        c.host = host
        c.path = "/join"
        var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(parts[1]))]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
            items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        c.queryItems = items
        return c.url
    }

    /// `zoommtg://zoom.us/join?confno=123&pwd=abc` → `https://zoom.us/j/123?pwd=abc`.
    private static func zoomWeb(_ url: URL) -> URL? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let confno = items.first(where: { $0.name == "confno" })?.value, !confno.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = url.host ?? "zoom.us"
        c.path = "/j/" + confno
        if let pwd = items.first(where: { $0.name == "pwd" })?.value { c.queryItems = [URLQueryItem(name: "pwd", value: pwd)] }
        return c.url
    }

    /// `https://teams.microsoft.com/l/meetup-join/…` → `msteams:/l/meetup-join/…` (path and query kept).
    private static func teamsNative(_ url: URL) -> URL? {
        guard url.host?.lowercased() == "teams.microsoft.com", url.path.lowercased().hasPrefix("/l/meetup-join/"),
              let range = url.absoluteString.range(of: "/l/") else { return nil }
        return URL(string: "msteams:" + url.absoluteString[range.lowerBound...])
    }

    /// `msteams:/l/meetup-join/…` → `https://teams.microsoft.com/l/meetup-join/…`.
    private static func teamsWeb(_ url: URL) -> URL? {
        guard let range = url.absoluteString.range(of: "/l/") else { return nil }
        return URL(string: "https://teams.microsoft.com" + url.absoluteString[range.lowerBound...])
    }
}
