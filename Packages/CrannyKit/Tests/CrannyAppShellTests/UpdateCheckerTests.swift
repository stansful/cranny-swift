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

/// Holds every request until `open()`, so two checks can overlap.
actor GatedUpdateTransport: UpdateTransport {
    private let answer: Data
    private var isOpen = false
    private(set) var requests: [URLRequest] = []

    init(answer: Data) { self.answer = answer }

    func open() { isOpen = true }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        while !isOpen { try await Task.sleep(for: .milliseconds(5)) }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])
        else { throw URLError(.badURL) }
        return (answer, response)
    }
}

/// A sleep the test ends by hand: records every wait; `release()` ends the waits so far. A cancelled wait throws,
/// as `Task.sleep` does.
@MainActor final class ManualSleeper {
    private(set) var waits: [TimeInterval] = []
    private var released = 0

    func sleep(_ wait: TimeInterval) async throws {
        waits.append(wait)
        let index = waits.count
        while released < index { try await Task.sleep(for: .milliseconds(5)) }
    }

    func release() { released = waits.count }
}

/// Polls `condition` for up to two seconds.
@MainActor func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

private func makeChecker(_ transport: any UpdateTransport, repository: String? = repository, version: String = "0.1.0",
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

@Test func aPrereleaseSwitchKeepsWhatIsStillTrue() throws {
    let stable = UpdateState.available(version: "0.2.0", notesURL: try page("v0.2.0"))
    let beta = UpdateState.available(version: "0.3.0-beta.1", notesURL: try page("v0.3.0-beta.1"))
    func after(_ state: UpdateState, includesPrereleases: Bool) -> UpdateState {
        UpdateChecker.state(state, afterPrereleasesChangedTo: includesPrereleases)
    }
    #expect(after(stable, includesPrereleases: true) == stable && after(stable, includesPrereleases: false) == stable)
    #expect(after(beta, includesPrereleases: false) == .idle)                      // pre-releases off: it no longer counts
    #expect(after(.upToDate, includesPrereleases: false) == .upToDate)              // still true on the stable channel
    #expect(after(.upToDate, includesPrereleases: true) == .idle)                   // a newer pre-release may exist
    #expect(after(.failed("x"), includesPrereleases: true) == .idle)
    #expect(after(.checking, includesPrereleases: false) == .checking && after(.idle, includesPrereleases: true) == .idle)
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

@Test func anAnswerThatCannotBeUsedFailsOnlyWhenTheUserAsked() async throws {
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil), .ok(latestFixture, etag: nil)])
    let settings = CrannyServices.preview().settings
    let checker = makeChecker(transport, version: "dev", settings: settings)       // the running version is not semver
    #expect(await checker.check(userInitiated: false) == .idle)                    // automatic: nothing changes
    #expect(settings[CoreSettings.lastUpdateCheck] != nil)                          // GitHub answered: next check in a day
    #expect(await checker.check() == .failed(UpdateFailure.badVersion.message))
}

@Test func checksAtTheSameTimeShareOneRequest() async throws {
    let transport = GatedUpdateTransport(answer: latestFixture)
    let checker = makeChecker(transport)
    let first = Task { await checker.check() }
    #expect(await eventually { await transport.requests.count == 1 })
    let second = Task { await checker.check(userInitiated: false) }
    try await Task.sleep(for: .milliseconds(50))                                    // the second check waits as well
    await transport.open()
    let expected = UpdateState.available(version: "0.2.0", notesURL: try page("v0.2.0"))
    let (one, two) = (await first.value, await second.value)
    #expect(one == expected && two == expected)
    #expect(await transport.requests.count == 1)
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

// MARK: - The schedule

@Test func theDailyCheckRunsAfterOneSleepAndFollowsTheSetting() async throws {
    let sleeper = ManualSleeper()
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil)])
    let settings = CrannyServices.preview().settings
    let checker = makeChecker(transport, settings: settings, sleep: { try await sleeper.sleep($0) })
    checker.start()
    defer { checker.stop() }
    #expect(await eventually { sleeper.waits == [UpdateChecker.launchDelay] })     // never checked: a minute after launch

    settings[CoreSettings.checksForUpdates] = false                                 // turned off before the sleep ends
    try await Task.sleep(for: .milliseconds(100))
    sleeper.release()
    try await Task.sleep(for: .milliseconds(100))
    #expect(await transport.requests.isEmpty && sleeper.waits.count == 1)

    settings[CoreSettings.checksForUpdates] = true                                  // on again: a new schedule
    #expect(await eventually { sleeper.waits.count == 2 })
    #expect(sleeper.waits.last == UpdateChecker.launchDelay)
    sleeper.release()
    let available = UpdateState.available(version: "0.2.0", notesURL: try page("v0.2.0"))
    #expect(await eventually { checker.state == available })
    #expect(await eventually { sleeper.waits.count == 3 })
    #expect((sleeper.waits.last ?? 0) > UpdateChecker.interval - 60)               // then a day later, one sleep
    #expect(await transport.requests.count == 1)
}

@Test func aFailedAutomaticCheckRetriesInAnHour() async throws {
    let sleeper = ManualSleeper()
    let transport = FakeUpdateTransport([.failure(.notConnectedToInternet)])
    let checker = makeChecker(transport, sleep: { try await sleeper.sleep($0) })
    checker.start()
    defer { checker.stop() }
    #expect(await eventually { sleeper.waits == [UpdateChecker.launchDelay] })
    sleeper.release()
    #expect(await eventually { sleeper.waits.count == 2 })
    #expect(sleeper.waits.last == UpdateChecker.retryDelay)
    #expect(await transport.requests.count == 1 && checker.state == .idle)         // nobody asked: no failure shown
}

@Test func turningPrereleasesOnAsksTheListTwoSecondsLater() async throws {
    let sleeper = ManualSleeper()
    let transport = FakeUpdateTransport([.ok(listFixture, etag: nil)])
    let settings = CrannyServices.preview().settings
    settings[CoreSettings.lastUpdateCheck] = Date()                                 // checked just now: next one in a day
    let checker = makeChecker(transport, settings: settings, sleep: { try await sleeper.sleep($0) })
    checker.start()
    defer { checker.stop() }
    #expect(await eventually { sleeper.waits.count == 1 })
    #expect((sleeper.waits.first ?? 0) > UpdateChecker.interval - 60)

    settings[CoreSettings.includesPrereleases] = true
    #expect(await eventually { sleeper.waits.count == 2 })
    #expect(sleeper.waits.last == 2)
    sleeper.release()
    let beta = UpdateState.available(version: "0.3.0-beta.1", notesURL: try page("v0.3.0-beta.1"))
    #expect(await eventually { checker.state == beta })
    let requests = await transport.requests
    #expect(requests.count == 1 && requests.first?.url?.absoluteString.hasSuffix("/releases?per_page=20") == true)
}

@Test func withAutomaticChecksOffThePrereleaseSwitchAsksNothing() async throws {
    let sleeper = ManualSleeper()
    let transport = FakeUpdateTransport([.ok(latestFixture, etag: nil), .ok(listFixture, etag: nil)])
    let settings = CrannyServices.preview().settings
    settings[CoreSettings.checksForUpdates] = false
    let checker = makeChecker(transport, settings: settings, sleep: { try await sleeper.sleep($0) })
    checker.start()
    defer { checker.stop() }
    let stable = await checker.check()                                              // checked by hand: 0.2.0
    settings[CoreSettings.includesPrereleases] = true
    try await Task.sleep(for: .milliseconds(100))
    #expect(checker.state == stable)                                                // still an update on either channel

    let beta = await checker.check()                                                // by hand again: the list
    #expect(beta == .available(version: "0.3.0-beta.1", notesURL: try page("v0.3.0-beta.1")))
    settings[CoreSettings.includesPrereleases] = false
    #expect(await eventually { checker.state == .idle })                           // the pre-release no longer counts
    #expect(await transport.requests.count == 2 && sleeper.waits.isEmpty)          // and nothing was asked by itself
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
