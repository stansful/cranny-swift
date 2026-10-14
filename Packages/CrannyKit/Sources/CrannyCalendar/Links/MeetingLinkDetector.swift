// CrannyCalendar/Links/MeetingLinkDetector.swift — finds the video-meeting link of an event (ARCHITECTURE.md
// §7.4). Search order: the event's URL, then its location, then its notes; within a field the earliest
// meeting link wins (dial-in numbers and "learn more" links come later in invitations). Redirect wrappers
// are unwrapped first. Pure and `nonisolated`; written from the services' public link formats.
import Foundation

/// A recognised meeting link. `url` is the unwrapped destination, exactly as the invitation gives it.
nonisolated struct MeetingLink: Hashable, Sendable {
    var service: MeetingService
    var url: URL
}

nonisolated enum MeetingLinkDetector {
    /// All meeting links of an event in search order (URL → location → notes), without duplicates.
    static func links(url: URL?, location: String?, notes: String?) -> [MeetingLink] {
        var found: [MeetingLink] = []
        func add(_ link: MeetingLink) { if !found.contains(link) { found.append(link) } }
        if let url, let link = classify(URLScanner.unwrap(url)) { add(link) }
        for field in [location, notes] {
            guard let field, !field.isEmpty else { continue }
            for link in links(in: field) { add(link) }
        }
        return found
    }

    /// The meeting links in one free-text field, in order of appearance.
    static func links(in text: String) -> [MeetingLink] {
        URLScanner.urls(in: text).compactMap { classify(URLScanner.unwrap($0)) }
    }

    /// The service a (already unwrapped) URL joins, or nil when it is not a meeting link.
    static func classify(_ url: URL) -> MeetingLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "zoommtg", "zoomus":
            return MeetingLink(service: .zoom, url: url)
        case "msteams":
            return MeetingLink(service: .teams, url: url)
        case "http", "https":
            break
        default:
            return nil
        }
        guard let host = url.host?.lowercased() else { return nil }
        let lowerPath = url.path.lowercased()
        let components = url.path.split(separator: "/").map(String.init)
        guard let service = service(host: host, lowerPath: lowerPath, components: components, url: url) else {
            return nil
        }
        return MeetingLink(service: service, url: url)
    }

    // MARK: - Per-service rules

    private static func service(host: String, lowerPath: String, components: [String], url: URL) -> MeetingService? {
        if matches(host, "zoom.us") || matches(host, "zoomgov.com") {
            return ["/j/", "/s/", "/w/", "/my/", "/wc/"].contains { lowerPath.hasPrefix($0) } ? .zoom : nil
        }
        if host == "meet.google.com" {
            return isMeetCode(components.first) || lowerPath.hasPrefix("/lookup/") ? .meet : nil
        }
        if ["teams.microsoft.com", "teams.live.com", "teams.microsoft.us", "gov.teams.microsoft.us",
            "dod.teams.microsoft.us", "teams.cloud.microsoft"].contains(host) {
            let joins = lowerPath.hasPrefix("/l/meetup-join/") || lowerPath.hasPrefix("/meet/")
                || lowerPath.hasPrefix("/l/meet/")
                || (url.query?.lowercased().contains("meetingjoin=true") ?? false)
            return joins ? .teams : nil
        }
        if matches(host, "webex.com") {
            // site/j.php?MTID=…, /meet/<user> (personal rooms), /join/<user>, web app joins, short /m/ links.
            let joins = lowerPath.contains("/j.php") || lowerPath.contains("/meet/") || lowerPath == "/meet"
                || lowerPath.hasPrefix("/join/") || lowerPath.hasPrefix("/wbxmjs/joinservice") || lowerPath.hasPrefix("/m/")
            return joins ? .webex : nil
        }
        if host == "facetime.apple.com" {
            return lowerPath.hasPrefix("/join") ? .facetime : nil
        }
        if host == "app.slack.com" {
            return lowerPath.hasPrefix("/huddle/") ? .slack : nil
        }
        if matches(host, "whereby.com") {
            let reserved: Set<String> = ["information", "user", "org", "login", "signup", "pricing", "blog", "help", "legal"]
            guard let room = components.first?.lowercased(), !reserved.contains(room) else { return nil }
            return .whereby
        }
        if host == "meet.goto.com" {
            return components.isEmpty ? nil : .goto
        }
        if matches(host, "gotomeeting.com") || host == "app.goto.com" {
            return lowerPath.hasPrefix("/join/") || lowerPath.hasPrefix("/meeting/") ? .goto : nil
        }
        if host == "meet.jit.si" || host == "8x8.vc" {
            return components.isEmpty ? nil : .jitsi
        }
        if host == "chime.aws" {
            return components.first.map { !$0.isEmpty && $0.allSatisfy(\.isNumber) } == true ? .chime : nil
        }
        if host == "app.chime.aws" {
            return lowerPath.hasPrefix("/meetings/") ? .chime : nil
        }
        return nil
    }

    /// `host` is `domain` or one of its subdomains (`acme.zoom.us`, `us02web.zoom.us`).
    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// Google Meet codes look like `abc-defg-hij` (lowercase letters).
    private static func isMeetCode(_ component: String?) -> Bool {
        guard let parts = component?.split(separator: "-", omittingEmptySubsequences: false), parts.count == 3 else { return false }
        let lengths = parts.map(\.count)
        return lengths == [3, 4, 3] && parts.allSatisfy { $0.allSatisfy { $0.isLetter && $0.isASCII } }
    }
}
