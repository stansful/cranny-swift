// CrannyAppShell/Services/UpdateChecker+GitHub.swift — the GitHub Releases side of `UpdateChecker`
// (ARCHITECTURE.md §7.11), all pure or `nonisolated` so tests drive it with fixtures: the repository setting,
// the request (ETag, no cookies, no identifiers), decoding, the version comparison and the transport.
// Cranny's only network access is the one request built here.
import CrannyCore
import Foundation

// MARK: - Configuration

nonisolated struct UpdateConfiguration: Equatable, Sendable {
    /// The Info.plist key that names the GitHub repository ("owner/repo"). Empty or missing disables the check.
    /// WP-Final sets it once the public repository exists (§10.18); until then every build has no update check.
    static let repositoryInfoKey = "CrannyGitHubRepository"

    /// "owner/repo", validated; nil = update checks are off in this build.
    var repository: String?
    /// `CFBundleShortVersionString` of the running app.
    var currentVersion: String

    init(repository: String?, currentVersion: String) {
        self.repository = repository.flatMap(Self.validRepository)
        self.currentVersion = currentVersion
    }

    /// The running app's configuration. Debug builds also accept `-CrannyGitHubRepository owner/repo` on the
    /// command line (the arguments domain of `UserDefaults`), to test against a scratch repository.
    static func main(bundle: Bundle = .main) -> UpdateConfiguration {
        var repository = bundle.object(forInfoDictionaryKey: repositoryInfoKey) as? String
        #if DEBUG
        if let override = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[repositoryInfoKey] as? String {
            repository = override
        }
        #endif
        return UpdateConfiguration(repository: repository, currentVersion: AppInfo.current(bundle).version)
    }

    /// GitHub's owner and repository name rules, loosely: letters, digits, "-", "_" and "." in two parts.
    static func validRepository(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              !parts.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return trimmed
    }
}

// MARK: - Releases

/// The fields of a GitHub release that the check reads (REST API "release" object).
nonisolated struct GitHubRelease: Codable, Equatable, Sendable {
    var tagName: String
    var htmlURL: URL?
    var isDraft: Bool
    var isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", isDraft = "draft", isPrerelease = "prerelease"
    }

    init(tagName: String, htmlURL: URL?, isDraft: Bool = false, isPrerelease: Bool = false) {
        self.tagName = tagName; self.htmlURL = htmlURL; self.isDraft = isDraft; self.isPrerelease = isPrerelease
    }
}

/// Which endpoint answers the question "what is the newest release?".
nonisolated enum ReleaseEndpoint: String, Codable, Sendable {
    /// `/releases/latest`: the newest published, non-draft, non-pre-release release.
    case latest
    /// `/releases?per_page=20`: recent releases incl. pre-releases (Settings ▸ General ▸ include pre-releases).
    case list

    init(includesPrereleases: Bool) { self = includesPrereleases ? .list : .latest }

    /// `perPage` applies to `.list` only (`per_page=1` tells "no stable release yet" from "no repository").
    func url(repository: String, perPage: Int = 20) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(repository)/releases" + (self == .latest ? "/latest" : "")
        if self == .list { components.queryItems = [URLQueryItem(name: "per_page", value: String(perPage))] }
        return components.url
    }

    /// Decodes one release (`latest`) or a list (`list`).
    func decode(_ data: Data) throws -> [GitHubRelease] {
        switch self {
        case .latest: [try JSONDecoder().decode(GitHubRelease.self, from: data)]
        case .list: try JSONDecoder().decode([GitHubRelease].self, from: data)
        }
    }
}

nonisolated enum UpdateRequest {
    /// A GET with GitHub's media type, a fixed product User-Agent (GitHub requires one; it carries no version,
    /// machine or user identifier), the stored ETag when there is one, and no cookies or caches.
    ///
    /// Every header on the wire (captured with a local server on macOS 27): `User-Agent: Cranny`,
    /// `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `If-None-Match` (only with a
    /// cached ETag), `Accept-Language: en`, plus the system's `Accept-Encoding` (compression) and, over HTTP/1.1,
    /// `Connection`. Accept-Language is pinned because CFNetwork would otherwise send the user's preferred
    /// language (a fingerprinting signal); an explicit value replaces the system's.
    static func make(url: URL, etag: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Cranny", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        if let etag, !etag.isEmpty { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return request
    }
}

/// The last good answer of an endpoint, kept so a `304 Not Modified` can be evaluated (caches directory).
nonisolated struct ReleaseCache: Codable, Equatable, Sendable {
    var repository: String
    var endpoint: ReleaseEndpoint
    var etag: String
    var releases: [GitHubRelease]

    /// The ETag to send: only for the same repository and endpoint.
    func etag(repository: String, endpoint: ReleaseEndpoint) -> String? {
        repository == self.repository && endpoint == self.endpoint ? etag : nil
    }
}

// MARK: - Evaluation

nonisolated enum UpdateEvaluator {
    /// Compares the newest eligible release with the running version. Tags that are not semantic versions and
    /// drafts are ignored; pre-releases count only when the user opted in.
    static func evaluate(_ releases: [GitHubRelease], currentVersion: String, includesPrereleases: Bool,
                         repository: String) -> UpdateState {
        guard let current = SemanticVersion(currentVersion) else { return .failed(UpdateFailure.badVersion.message) }
        var newest: (release: GitHubRelease, version: SemanticVersion)?
        for release in releases where !release.isDraft && (includesPrereleases || !release.isPrerelease) {
            guard let version = SemanticVersion(release.tagName), includesPrereleases || version.prerelease == nil else { continue }
            if newest.map({ $0.version < version }) ?? true { newest = (release, version) }
        }
        guard let (release, version) = newest, current < version else { return .upToDate }
        guard let page = releasePage(release, repository: repository) else { return .failed(UpdateFailure.unreadable.message) }
        return .available(version: version.description, notesURL: page)
    }

    /// The release page to open: GitHub's `html_url` when it really points at github.com over HTTPS, else the
    /// page built from the tag. Never a URL from elsewhere.
    static func releasePage(_ release: GitHubRelease, repository: String) -> URL? {
        if let url = release.htmlURL, url.scheme == "https", url.host() == "github.com" { return url }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/releases/tag/\(release.tagName)"
        return components.url
    }
}

/// Why a check failed, as a localized one-liner (Settings ▸ About and the result alert show it).
nonisolated enum UpdateFailure: Error, Equatable, Sendable {
    /// `repositoryNotFound`: GitHub does not know `CrannyGitHubRepository` (wrong, renamed or private), HTTP 404.
    case notConfigured, offline, rateLimited, server(Int), repositoryNotFound, unreadable, badVersion

    /// The failure an HTTP status other than 200 and 304 stands for. A 404 from `/releases/latest` is first
    /// checked against the list, since it also means "no stable release yet" (`UpdateChecker.latestNotFound`).
    static func http(_ status: Int) -> UpdateFailure {
        switch status {
        case 403, 429: .rateLimited
        case 404: .repositoryNotFound
        default: .server(status)
        }
    }

    var message: String {
        switch self {
        case .notConfigured:
            String(localized: "Update checks are not available in this build.", bundle: .module,
                   comment: "Update check: failure reason, no GitHub repository configured")
        case .repositoryNotFound:
            String(localized: "GitHub couldn't find Cranny's releases. Try again later.", bundle: .module,
                   comment: "Update check: failure reason, HTTP 404 (the configured repository does not exist)")
        case .offline:
            String(localized: "GitHub couldn't be reached. Check your internet connection and try again.", bundle: .module,
                   comment: "Update check: failure reason, network error")
        case .rateLimited:
            String(localized: "GitHub is limiting requests right now. Try again later.", bundle: .module,
                   comment: "Update check: failure reason, HTTP 403/429")
        case .server(let status):
            String(localized: "GitHub answered with an error (\(status)). Try again later.", bundle: .module,
                   comment: "Update check: failure reason, other HTTP status; the number is the status code")
        case .unreadable, .badVersion:
            String(localized: "The release information couldn't be read.", bundle: .module,
                   comment: "Update check: failure reason, unexpected response")
        }
    }
}

// MARK: - Transport

/// The single network call, behind a protocol so tests answer with fixtures.
nonisolated protocol UpdateTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// An ephemeral session: no cookies, no URL cache, no credential storage; nothing persists between checks
/// except the ETag Cranny stores itself.
nonisolated final class URLSessionUpdateTransport: UpdateTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    @concurrent func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateFailure.unreadable }
        return (data, http)
    }
}
