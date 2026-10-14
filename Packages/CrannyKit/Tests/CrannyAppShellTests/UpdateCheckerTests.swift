// WP16: the GitHub Releases update check (ARCHITECTURE.md §7.11) against fixtures — no network.
// The fixtures follow the REST API's "release" object (only a few of its fields are read; the rest must be ignored).
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell

// MARK: - Fixtures

private let latestFixture = Data("""
{
  "url": "https://api.github.com/repos/octo/cranny/releases/101",
  "html_url": "https://github.com/octo/cranny/releases/tag/v0.2.0",
  "id": 101,
  "tag_name": "v0.2.0",
  "target_commitish": "main",
  "name": "Cranny 0.2.0",
  "draft": false,
  "prerelease": false,
  "created_at": "2026-10-01T10:00:00Z",
  "published_at": "2026-10-01T10:05:00Z",
  "author": { "login": "octo", "id": 1 },
  "assets": [ { "name": "Cranny-0.2.0.zip", "size": 4200000,
                "browser_download_url": "https://github.com/octo/cranny/releases/download/v0.2.0/Cranny-0.2.0.zip" } ],
  "body": "## What's new\\n- Calmer light"
}
""".utf8)

private let listFixture = Data("""
[
  { "tag_name": "v0.4.0", "html_url": "https://github.com/octo/cranny/releases/tag/untagged-1", "draft": true, "prerelease": false },
  { "tag_name": "nightly", "html_url": "https://github.com/octo/cranny/releases/tag/nightly", "draft": false, "prerelease": true },
  { "tag_name": "v0.3.0-beta.1", "html_url": "https://github.com/octo/cranny/releases/tag/v0.3.0-beta.1", "draft": false, "prerelease": true,
    "assets": [], "body": null },
  { "tag_name": "v0.2.0", "html_url": "https://github.com/octo/cranny/releases/tag/v0.2.0", "draft": false, "prerelease": false },
  { "tag_name": "v0.1.0", "html_url": "https://github.com/octo/cranny/releases/tag/v0.1.0", "draft": false, "prerelease": false }
]
""".utf8)

private let repository = "octo/cranny"

/// Answers requests from a queue and records them.
actor FakeUpdateTransport: UpdateTransport {
    enum Answer { case ok(Data, etag: String?), status(Int), failure(URLError.Code) }
    private var answers: [Answer]
    private(set) var requests: [URLRequest] = []

    init(_ answers: [Answer]) { self.answers = answers }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !answers.isEmpty, let url = request.url else { throw URLError(.cannotConnectToHost) }
        switch answers.removeFirst() {
        case .ok(let data, let etag):
            let headers = etag.map { ["ETag": $0] } ?? [:]
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) ?? HTTPURLResponse())
        case .status(let code):
            return (Data(), HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:]) ?? HTTPURLResponse())
        case .failure(let code):
            throw URLError(code)
        }
    }
}

private func makeChecker(_ transport: FakeUpdateTransport, repository: String? = repository, version: String = "0.1.0",
                         settings: SettingsStore = CrannyServices.preview().settings,
                         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { _ in throw CancellationError() }) -> UpdateChecker {
    UpdateChecker(settings: settings, configuration: UpdateConfiguration(repository: repository, currentVersion: version),
                  paths: .temporary(), transport: transport, sleep: sleep)
}

private func page(_ tag: String) throws -> URL { try #require(URL(string: "https://github.com/octo/cranny/releases/tag/\(tag)")) }

// MARK: - Configuration and request

@Test func repositorySlugsAreValidated() {
    #expect(UpdateConfiguration.validRepository("octo/cranny") == "octo/cranny")
    #expect(UpdateConfiguration.validRepository("  octo/cranny.app \n") == "octo/cranny.app")
    for bad in ["", "octo", "octo/", "/cranny", "a/b/c", "../etc", "octo/..", "oc to/cranny", "octo/cranny?x=1", "octo/cranny#x"] {
        #expect(UpdateConfiguration.validRepository(bad) == nil, "\(bad)")
    }
    #expect(UpdateConfiguration(repository: "", currentVersion: "0.1.0").repository == nil)     // empty Info.plist value: off
    #expect(UpdateConfiguration.repositoryInfoKey == "CrannyGitHubRepository")
}

@Test func endpointsAndRequestCarryNoIdentifiers() throws {
    let latest = try #require(ReleaseEndpoint.latest.url(repository: repository))
    #expect(latest.absoluteString == "https://api.github.com/repos/octo/cranny/releases/latest")
    let list = try #require(ReleaseEndpoint(includesPrereleases: true).url(repository: repository))
    #expect(list.absoluteString == "https://api.github.com/repos/octo/cranny/releases?per_page=20")

    let request = UpdateRequest.make(url: latest, etag: "W/\"abc\"")
    #expect(request.httpMethod == "GET" && !request.httpShouldHandleCookies)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Cranny")
    #expect(request.allHTTPHeaderFields?.keys.sorted() == ["Accept", "If-None-Match", "User-Agent", "X-GitHub-Api-Version"])
    #expect(UpdateRequest.make(url: latest, etag: nil).value(forHTTPHeaderField: "If-None-Match") == nil)
}

// MARK: - Decoding and comparison

@Test func releasesDecodeFromGitHubJSON() throws {
    let latest = try ReleaseEndpoint.latest.decode(latestFixture)
    #expect(latest == [GitHubRelease(tagName: "v0.2.0", htmlURL: try page("v0.2.0"))])
    let list = try ReleaseEndpoint.list.decode(listFixture)
    #expect(list.count == 5 && list[0].isDraft && list[2].isPrerelease)
    #expect(throws: DecodingError.self) { try ReleaseEndpoint.latest.decode(Data("{\"message\":\"Not Found\"}".utf8)) }
}

@Test func theNewestEligibleReleaseIsCompared() throws {
    let list = try ReleaseEndpoint.list.decode(listFixture)
    func evaluate(_ current: String, prereleases: Bool) -> UpdateState {
        UpdateEvaluator.evaluate(list, currentVersion: current, includesPrereleases: prereleases, repository: repository)
    }
    #expect(evaluate("0.1.0", prereleases: false) == .available(version: "0.2.0", notesURL: try page("v0.2.0")))
    #expect(evaluate("0.1.0", prereleases: true) == .available(version: "0.3.0-beta.1", notesURL: try page("v0.3.0-beta.1")))
    #expect(evaluate("0.2.0", prereleases: false) == .upToDate)                     // the draft 0.4.0 never counts
    #expect(evaluate("0.3.0", prereleases: true) == .upToDate)
    #expect(evaluate("0.2.0-beta.2", prereleases: false) == .available(version: "0.2.0", notesURL: try page("v0.2.0")))
    #expect(evaluate("0.10.0", prereleases: true) == .upToDate)                     // numeric, not lexical
    #expect(UpdateEvaluator.evaluate([], currentVersion: "0.1.0", includesPrereleases: false, repository: repository) == .upToDate)
    if case .failed = evaluate("dev", prereleases: false) {} else { Issue.record("an unreadable running version must fail") }
}

@Test func onlyGitHubReleasePagesAreOpened() throws {
    let evil = GitHubRelease(tagName: "v9.0.0", htmlURL: URL(string: "https://evil.example/download"))
    #expect(UpdateEvaluator.releasePage(evil, repository: repository) == (try page("v9.0.0")))
    let plain = GitHubRelease(tagName: "v9.0.0", htmlURL: URL(string: "http://github.com/octo/cranny/releases/tag/v9.0.0"))
    #expect(UpdateEvaluator.releasePage(plain, repository: repository)?.scheme == "https")
    let missing = GitHubRelease(tagName: "v9.0.0", htmlURL: nil)
    #expect(UpdateEvaluator.releasePage(missing, repository: repository) == (try page("v9.0.0")))
}

@Test func automaticChecksAreDailyWithoutPolling() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(UpdateChecker.delayUntilNextCheck(lastCheck: nil, now: now) == UpdateChecker.launchDelay)
    #expect(UpdateChecker.delayUntilNextCheck(lastCheck: now.addingTimeInterval(-3 * 86_400), now: now) == UpdateChecker.launchDelay)
    #expect(UpdateChecker.delayUntilNextCheck(lastCheck: now.addingTimeInterval(-3600), now: now) == 86_400 - 3600)
    #expect(UpdateChecker.delayUntilNextCheck(lastCheck: now.addingTimeInterval(3600), now: now) == UpdateChecker.interval)   // clock moved back
}

// MARK: - The checker

@Test func theSecondCheckRevalidatesWithTheETag() async throws {
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: "W/\"abc\""), .status(304)])
    let settings = CrannyServices.preview().settings
    let checker = makeChecker(transport, settings: settings)
    #expect(checker.isConfigured && checker.state == .idle)
    let first = await checker.check()
    #expect(first == .available(version: "0.2.0", notesURL: try page("v0.2.0")) && checker.state == first)
    #expect(settings[CoreSettings.lastUpdateCheck] != nil)
    let second = await checker.check()                                              // 304 Not Modified → the cached answer
    #expect(second == first)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
}

@Test func switchingToPrereleasesAsksTheListWithoutTheOldETag() async throws {
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: "W/\"latest\""), .ok(listFixture, etag: "W/\"list\"")])
    let settings = CrannyServices.preview().settings
    let checker = makeChecker(transport, settings: settings)
    await checker.check()
    settings[CoreSettings.includesPrereleases] = true
    let result = await checker.check()
    #expect(result == .available(version: "0.3.0-beta.1", notesURL: try page("v0.3.0-beta.1")))
    let requests = await transport.requests
    #expect(requests[1].url?.absoluteString.hasSuffix("/releases?per_page=20") == true)
    #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
}

@Test func failuresAreReportedOnlyWhenTheUserAsked() async throws {
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil), .failure(.notConnectedToInternet),
                                         .failure(.notConnectedToInternet), .status(403), .status(502), .status(404),
                                         .ok(Data("<html>".utf8), etag: nil)])
    let checker = makeChecker(transport)
    let available = await checker.check(userInitiated: false)
    #expect(await checker.check(userInitiated: false) == available)                 // offline in the background: keep it
    #expect(await checker.check(userInitiated: true) == .failed(UpdateFailure.offline.message))
    #expect(await checker.check() == .failed(UpdateFailure.rateLimited.message))
    #expect(await checker.check() == .failed(UpdateFailure.server(502).message))
    #expect(await checker.check() == .upToDate)                                    // 404: nothing published yet
    #expect(await checker.check() == .failed(UpdateFailure.unreadable.message))
}

@Test func withoutARepositoryNothingIsRequested() async throws {
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil)])
    var slept = false
    let checker = makeChecker(transport, repository: nil, sleep: { _ in slept = true })
    #expect(!checker.isConfigured)
    checker.start()
    #expect(await checker.check() == .failed(UpdateFailure.notConfigured.message))
    #expect(await transport.requests.isEmpty && !slept)
}

@Test func theDailyCheckRunsAfterOneSleepAndFollowsTheSetting() async throws {
    final class Sleeper { var waits: [TimeInterval] = [] }
    let sleeper = Sleeper()
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil)])
    let settings = CrannyServices.preview().settings
    let checker = makeChecker(transport, settings: settings, sleep: { wait in
        sleeper.waits.append(wait)
        if sleeper.waits.count > 1 { throw CancellationError() }                  // stop after the first round
    })
    checker.start()
    defer { checker.stop() }
    for _ in 0..<80 where checker.state == .idle { try await Task.sleep(for: .milliseconds(25)) }
    #expect(checker.state == .available(version: "0.2.0", notesURL: try page("v0.2.0")))
    #expect(sleeper.waits.first == UpdateChecker.launchDelay)                       // never checked before
    for _ in 0..<40 where sleeper.waits.count < 2 { try await Task.sleep(for: .milliseconds(25)) }
    #expect(sleeper.waits.count == 2 && (sleeper.waits.last ?? 0) > UpdateChecker.interval - 60)    // then a day later

    settings[CoreSettings.checksForUpdates] = false                                 // Settings ▸ General ▸ Updates off
    try await Task.sleep(for: .milliseconds(100))
    #expect(await transport.requests.count == 1 && sleeper.waits.count == 2)
}

// MARK: - The menu's result alert

@Test func theAlertSaysWhatTheCheckFound() throws {
    let url = try page("v0.2.0")
    let available = try #require(UpdateAlert.content(for: .available(version: "0.2.0", notesURL: url), currentVersion: "0.1.0"))
    #expect(available.title.contains("0.2.0") && available.message.contains("0.1.0"))
    #expect(available.link == url && available.secondaryButton != nil)
    let upToDate = try #require(UpdateAlert.content(for: .upToDate, currentVersion: "0.1.0"))
    #expect(upToDate.message.contains("0.1.0") && upToDate.link == nil && upToDate.secondaryButton == nil)
    let failed = try #require(UpdateAlert.content(for: .failed("GitHub is down"), currentVersion: "0.1.0"))
    #expect(failed.message == "GitHub is down" && failed.link == nil)
    #expect(UpdateAlert.content(for: .idle, currentVersion: "0.1.0") == nil)
    #expect(UpdateAlert.content(for: .checking, currentVersion: "0.1.0") == nil)
}
