// CrannyCalendar/Links/URLScanner.swift — finds URLs in free text (event URL, location, notes) and unwraps the
// redirect wrappers mail systems put around them (Outlook SafeLinks, Teams' safelinks page, Google redirects,
// Proofpoint URL Defense). Pure and `nonisolated`: it runs inside `EventKitSource`, off the main actor.
import Foundation

nonisolated enum URLScanner {
    /// Every URL in `text`, in order of appearance. HTML entities (`&amp;`) are decoded first, and trailing
    /// punctuation that belongs to the sentence ("…/j/123." or "(https://…)") is dropped.
    static func urls(in text: String) -> [URL] {
        let decoded = decodeEntities(text)
        var out: [URL] = []
        for match in decoded.matches(of: candidate) {
            let raw = trimTrailingPunctuation(String(decoded[match.range]))
            if let url = URL(string: raw), url.scheme != nil { out.append(url) }
        }
        return out
    }

    /// `text` with its URLs removed and leftover separators trimmed ("Room 4; https://…" → "Room 4").
    static func removingURLs(from text: String) -> String {
        let decoded = decodeEntities(text)
        var result = decoded
        for match in decoded.matches(of: candidate).reversed() {
            result.replaceSubrange(match.range, with: " ")
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";,|·-–—:()[]<>"))
        let collapsed = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.trimmingCharacters(in: separators)
    }

    /// Follows known redirect wrappers (nested ones too, at most four levels) to the real destination.
    static func unwrap(_ url: URL) -> URL {
        var current = url
        for _ in 0..<4 {
            guard let next = unwrapOnce(current), next != current else { return current }
            current = next
        }
        return current
    }

    // MARK: - Internals

    /// A scheme we care about, then everything up to whitespace or a character that cannot end a URL in prose.
    /// (A computed property: `Regex` is not `Sendable`, so it cannot be a shared static constant.)
    private static var candidate: Regex<Substring> { #/(?i)(?:https?://|zoommtg://|zoomus://|msteams:/{0,2})[^\s<>"'`{}|\\^\[\]]+/# }

    private static func trimTrailingPunctuation(_ raw: String) -> String {
        var s = Substring(raw)
        while let last = s.last, ".,;:!?)*'\"".contains(last) {
            // Keep a closing parenthesis that closes one inside the URL (Wikipedia-style links).
            if last == ")" && s.filter({ $0 == "(" }).count >= s.filter({ $0 == ")" }).count { break }
            s = s.dropLast()
        }
        return String(s)
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func unwrapOnce(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        if host.hasSuffix("safelinks.protection.outlook.com") {
            return queryURL(url, names: ["url"])                        // Outlook / Defender SafeLinks
        }
        if host.hasSuffix("teams.cdn.office.net"), path.contains("safelinks") {
            return queryURL(url, names: ["url"])                        // Teams' own SafeLinks page
        }
        if (host == "google.com" || host.hasPrefix("www.google.")) && path == "/url" {
            return queryURL(url, names: ["q", "url"])                   // Google Calendar / Gmail redirect
        }
        if host == "urldefense.com", path.hasPrefix("/v3/__") {
            return proofpointV3(url)
        }
        if host == "urldefense.proofpoint.com", path.hasPrefix("/v2/url") {
            return proofpointV2(url)
        }
        return nil
    }

    private static func queryURL(_ url: URL, names: [String]) -> URL? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in names {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value,
               let target = URL(string: value), target.scheme != nil {
                return target
            }
        }
        return nil
    }

    /// `https://urldefense.com/v3/__https://zoom.us/j/1__;!!abc$` → `https://zoom.us/j/1`.
    private static func proofpointV3(_ url: URL) -> URL? {
        let s = url.absoluteString
        guard let open = s.range(of: "/v3/__") else { return nil }
        let rest = s[open.upperBound...]
        let inner = rest.range(of: "__;").map { rest[..<$0.lowerBound] } ?? rest
        return URL(string: String(inner))
    }

    /// `…/v2/url?u=https-3A__zoom.us_j_1&d=…` → `https://zoom.us/j/1` ("-" stands for "%", "_" for "/").
    private static func proofpointV2(_ url: URL) -> URL? {
        guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "u" })?.value else { return nil }
        let percent = encoded.replacingOccurrences(of: "-", with: "%").replacingOccurrences(of: "_", with: "/")
        return percent.removingPercentEncoding.flatMap(URL.init(string:))
    }
}
