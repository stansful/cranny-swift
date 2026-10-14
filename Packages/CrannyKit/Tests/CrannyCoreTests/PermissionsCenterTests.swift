import Foundation
import Testing
@testable import CrannyCore

// PermissionsCenter's Automation cache (§10.20 #27): answers are asked off the main actor through an injected probe,
// kept per app, and asked again only on refresh, after a request or for a caller that needs a fresh answer. No test
// queries TCC: every center here gets a recording probe.

/// The answers a probe gives per app and every question it was asked (`ask` true = the request that may prompt).
private actor AutomationAnswers {
    var answers: [String: PermissionStatus] = [:]
    private(set) var questions: [(bundleID: String, ask: Bool)] = []
    /// While true, every question waits for `release()` (an answer still on its way).
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ answers: [String: PermissionStatus]) { self.answers = answers }

    /// The answer as it stood when the question was asked (a held answer lands late, unchanged).
    func answer(_ bundleID: String, ask: Bool) async -> PermissionStatus {
        questions.append((bundleID, ask))
        let answer = answers[bundleID] ?? .unknown
        if holds { await withCheckedContinuation { waiting.append($0) } }
        return answer
    }

    func set(_ status: PermissionStatus, for bundleID: String) { answers[bundleID] = status }
    func hold(_ on: Bool) { holds = on }
    func release() {
        let all = waiting
        waiting.removeAll()
        for continuation in all { continuation.resume() }
    }
    var count: Int { questions.count }
    var asks: [Bool] { questions.map(\.ask) }
}

@MainActor private func center(_ answers: AutomationAnswers) -> PermissionsCenter {
    PermissionsCenter(automationProbe: { id, ask in await answers.answer(id, ask: ask) })
}

/// Waits for `condition` (a generous bound, never a short real-time wait: §9.6).
@MainActor private func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<3000 { if await condition() { return }; try? await Task.sleep(for: .milliseconds(10)) }
}

private let music = "com.apple.Music"
private let spotify = "com.spotify.client"

/// A view body reading an app's status never queries macOS itself: the first read answers "not known yet" and starts
/// one query; later reads use the cached answer, however often a body runs.
@MainActor @Test func automationStatusIsCachedAndNeverAskedSynchronously() async {
    let answers = AutomationAnswers([music: .granted])
    let permissions = center(answers)
    let kind = PermissionKind.automation(bundleID: music)
    #expect(permissions.knownStatus(kind) == nil)                  // a spinner, not a wrong status
    #expect(permissions.status(kind) == .unknown)                  // the compatibility read says "unknown" meanwhile
    #expect(permissions.knownStatus(kind) == nil)
    await eventually { permissions.knownStatus(kind) != nil }
    #expect(permissions.knownStatus(kind) == .granted && permissions.status(kind) == .granted)
    for _ in 0..<20 { _ = permissions.status(kind); _ = permissions.knownStatus(kind) }   // body evaluations
    #expect(await answers.count == 1)                              // one query for all those reads
    #expect(await answers.asks == [false])                         // and it never prompts
}

/// `refresh()` asks again for every app already known (off the main actor) and keeps the old answer meanwhile;
/// other apps are not asked for.
@MainActor @Test func refreshAsksAgainForKnownApps() async {
    let answers = AutomationAnswers([music: .notDetermined, spotify: .denied])
    let permissions = center(answers)
    let kind = PermissionKind.automation(bundleID: music)
    _ = permissions.knownStatus(kind)
    await eventually { permissions.knownStatus(kind) != nil }
    #expect(permissions.status(kind) == .notDetermined)

    await answers.set(.granted, for: music)                         // granted in System Settings meanwhile
    await answers.hold(true)
    permissions.refresh()
    await eventually { await answers.count == 2 }
    #expect(permissions.status(kind) == .notDetermined)             // the row keeps its answer while asking
    await answers.release()
    await eventually { permissions.status(kind) == .granted }
    #expect(permissions.status(kind) == .granted)
    #expect(await answers.questions.map(\.bundleID) == [music, music])   // Spotify was never shown, never asked
}

/// After a request, the request's own answer is stored; a query that started before it and lands later is dropped.
@MainActor @Test func aRequestUpdatesTheCacheAndWinsOverAnOlderQuery() async {
    let answers = AutomationAnswers([music: .notDetermined])
    let permissions = center(answers)
    let kind = PermissionKind.automation(bundleID: music)
    await answers.hold(true)
    _ = permissions.knownStatus(kind)                               // a first query, still on its way
    await eventually { await answers.count == 1 }
    await answers.hold(false)
    await answers.set(.granted, for: music)                         // the person clicks Allow in the prompt
    let answer = await permissions.request(kind)
    #expect(answer == .granted && permissions.status(kind) == .granted)
    #expect(await answers.asks == [false, true])
    await answers.release()                                         // the old query lands: "not determined"
    for _ in 0..<5 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(50))
    #expect(permissions.status(kind) == .granted)
}

/// A denial a feature observed (an Apple Event refused with −1743) is kept even if an older query lands later;
/// `currentStatus` asks now and updates the cache.
@MainActor @Test func recordedDenialsAndFreshAnswers() async {
    let answers = AutomationAnswers([spotify: .granted])
    let permissions = center(answers)
    let kind = PermissionKind.automation(bundleID: spotify)
    await answers.hold(true)
    _ = permissions.knownStatus(kind)
    await eventually { await answers.count == 1 }
    permissions.record(.denied, for: kind)
    #expect(permissions.status(kind) == .denied)
    await answers.release()
    await answers.hold(false)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(permissions.status(kind) == .denied)                    // the stale "granted" was dropped

    #expect(await permissions.currentStatus(kind) == .granted)      // asked now: allowed again in System Settings
    #expect(permissions.status(kind) == .granted)
    #expect(await answers.asks == [false, false])
}

/// The real probe never prompts with `ask` false and needs no running player: an app that is not running (or not
/// installed) answers "unknown".
@Test func theSystemProbeAnswersUnknownForAnAppThatIsNotRunning() async {
    #expect(await PermissionsCenter.systemAutomationStatus("com.example.cranny.not-installed", ask: false) == .unknown)
}
