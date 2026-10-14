// The Apple Events fallback off the main actor (ARCHITECTURE.md §6.5): the serial script runner, and the session's
// ordered queue driven by a fake runner. No test runs a script against a player or listens to the user's players.
import AppKit
import CrannyCore
import Foundation
import os
import Testing
@testable import CrannyMedia

/// A runner driven by the test: records every script, answers with `answer`, or (while `holds`) keeps each script
/// waiting until `release` — a player that does not answer.
nonisolated final class FakeScriptRunner: AppleScriptRunning, @unchecked Sendable {   // test-only; used on the main actor
    private(set) var scripts: [PlayerScript] = []
    var answer: (PlayerScript) -> ScriptOutcome = { _ in .value(ScriptValue()) }
    var holds = false
    private var held: [(script: PlayerScript, reply: CheckedContinuation<ScriptOutcome, Never>)] = []

    var bodies: [String] { scripts.map(\.body) }
    var heldCount: Int { held.count }

    func run(_ script: PlayerScript) async -> ScriptOutcome {
        scripts.append(script)
        guard holds else { return answer(script) }
        return await withCheckedContinuation { held.append((script, $0)) }
    }

    /// Answers the oldest waiting script (with `outcome`, or what `answer` says).
    func release(_ outcome: ScriptOutcome? = nil) {
        guard !held.isEmpty else { return }
        let next = held.removeFirst()
        next.reply.resume(returning: outcome ?? answer(next.script))
    }
}

/// A session with a fake runner, a manual clock and no notification observers; collects what it reports.
@MainActor final class SessionHarness {
    let runner = FakeScriptRunner()
    let clock = ManualClock()
    let permitted = PermittedPlayers()
    private(set) var events: [ProviderEvent] = []
    private(set) var finished = false
    let session: AppleScriptSession

    init() {
        let permitted = permitted
        session = AppleScriptSession(isPermitted: { permitted.ids.contains($0) }, runner: runner, clock: clock,
                                     observesPlayers: false)
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self)
        session.start(continuation)
        Task { [weak self] in
            for await event in stream { self?.events.append(event) }
            self?.finished = true
        }
    }

    /// Events after the initial "nothing playing".
    var reported: [ProviderEvent] { Array(events.dropFirst()) }

    var snapshots: [NowPlaying?] {
        reported.compactMap { if case .nowPlaying(let np) = $0 { np } else { nil } }
    }

    /// Starts `send` without waiting for it; the answer lands in the returned box.
    func sendLater(_ command: MediaCommand) -> Answer {
        let answer = Answer()
        Task { answer.value = await session.send(command) }
        return answer
    }
}

@MainActor final class PermittedPlayers {
    var ids: Set<String> = [ScriptablePlayer.music.bundleID, ScriptablePlayer.spotify.bundleID]
}

@MainActor final class Answer {
    var value: Bool?
}

private enum Payload {
    static func music(_ title: String, state: String = "Playing") -> [String: String] {
        ["Name": title, "Artist": "The Example Band", "Album": "Night Signals", "Total Time": "215000", "Player State": state,
         "PersistentID": "id-\(title)"]
    }
    static func spotify(_ title: String, position: Double = 84.5) -> [String: String] {
        ["Name": title, "Artist": "The Example Band", "Duration": "215000", "Player State": "Playing",
         "Playback Position": "\(position)", "Track ID": "spotify:track:\(title)"]
    }
}

@Suite("Apple Events fallback: session") @MainActor struct AppleScriptSessionTests {
    private let position = ScriptablePlayer.positionScript
    private let artwork = ScriptablePlayer.artworkScript

    @Test func musicAsksForPositionThenArtworkOncePerTrack() async throws {
        let h = SessionHarness()
        h.runner.answer = { script in
            script.body == ScriptablePlayer.positionScript ? .value(ScriptValue(number: 42)) : .value(ScriptValue(binary: Data([1, 2, 3])))
        }
        h.session.receive(.music, Payload.music("One"))
        await settle()
        #expect(h.runner.bodies == [position, artwork])
        #expect(h.runner.scripts.allSatisfy { $0.bundleID == "com.apple.Music" })
        let np = try #require(h.snapshots.first ?? nil)
        #expect(np.title == "One")
        #expect(np.elapsed == 42)
        #expect(np.timestamp == h.clock.now)
        #expect(h.reported.last == .artwork(trackKey: np.trackKey, data: Data([1, 2, 3])))

        h.session.receive(.music, Payload.music("One", state: "Paused"))            // same track: no second artwork
        await settle()
        #expect(h.runner.bodies == [position, artwork, position])
        #expect(h.snapshots.last??.isPlaying == false)
    }

    @Test func spotifyPayloadNeedsNoScript() async throws {
        let h = SessionHarness()
        h.session.receive(.spotify, Payload.spotify("Two", position: 12))
        await settle()
        #expect(h.runner.scripts.isEmpty)
        let np = try #require(h.snapshots.first ?? nil)
        #expect(np.elapsed == 12)
    }

    @Test func aSlowPlayerNeverReordersSnapshots() async throws {
        let h = SessionHarness()
        h.runner.holds = true
        h.session.receive(.music, Payload.music("A"))
        await settle()
        #expect(h.runner.heldCount == 1)                    // A's position script is waiting; the main actor is free
        h.session.receive(.spotify, Payload.spotify("S"))   // queued behind A, never ahead of it
        h.session.receive(.music, Payload.music("B"))
        h.session.receive(.music, Payload.music("C"))       // replaces B, which has not started
        await settle()
        #expect(h.snapshots.isEmpty)

        h.runner.release(.value(ScriptValue(number: 1)))    // A's position
        await settle()
        h.runner.release(.value(ScriptValue()))             // A's artwork (none)
        await settle()
        h.runner.release(.value(ScriptValue(number: 3)))    // C's position
        await settle()
        h.runner.release(.value(ScriptValue()))             // C's artwork
        await settle()
        #expect(h.snapshots.map { $0?.title } == ["A", "S", "C"])
        #expect(h.runner.bodies == [position, artwork, position, artwork])
        #expect(h.runner.heldCount == 0)
    }

    @Test func commandsRunInOrderAfterQueuedWork() async throws {
        let h = SessionHarness()
        h.runner.holds = true
        h.session.receive(.music, Payload.music("A"))
        await settle()
        let pause = h.sendLater(.pause)
        let next = h.sendLater(.nextTrack)
        await settle()
        #expect(pause.value == nil && next.value == nil)    // waiting behind A's scripts
        for _ in 0..<4 {
            h.runner.release()
            await settle()
        }
        #expect(h.runner.bodies == [position, artwork, "pause", "next track"])
        #expect(pause.value == true)
        #expect(next.value == true)
    }

    @Test func aCommandThatWaitedPastTheTimeoutIsNotSent() async throws {
        let h = SessionHarness()
        h.runner.holds = true
        h.session.receive(.music, Payload.music("A"))
        await settle()
        let play = h.sendLater(.play)
        await settle()
        await h.clock.advance(by: .seconds(3))              // the player hangs for the whole timeout
        h.runner.release(.failed(code: -1712))
        await settle()
        h.runner.release(.failed(code: -1712))
        await settle()
        #expect(play.value == false)
        #expect(!h.runner.bodies.contains("play"))
    }

    @Test func aCommandWithoutPlayerOrRunningAppFails() async {
        let h = SessionHarness()
        #expect(await h.session.send(.play) == false)       // no player yet
        #expect(h.runner.scripts.isEmpty)
        h.session.receive(.spotify, Payload.spotify("S"))
        await settle()
        h.runner.answer = { _ in .notRunning }
        #expect(await h.session.send(.play) == false)
        h.runner.answer = { _ in .value(ScriptValue()) }
        #expect(await h.session.send(.play) == true)
        #expect(h.runner.bodies == ["play", "play"])
    }

    @Test func denialIsReportedOncePerPlayer() async {
        let h = SessionHarness()
        h.runner.answer = { _ in .failed(code: AppleScriptSession.notPermitted) }
        h.session.receive(.music, Payload.music("A"))
        await settle()
        h.session.receive(.music, Payload.music("B"))
        await settle()
        let denials = h.reported.filter { $0 == .permissionDenied(bundleID: "com.apple.Music") }
        #expect(denials.count == 1)
        #expect(h.snapshots.compactMap { $0?.title } == ["A", "B"])         // metadata still flows
    }

    @Test func noScriptRunsWithoutAutomation() async throws {
        let h = SessionHarness()
        h.permitted.ids = []
        h.session.receive(.music, Payload.music("A"))
        await settle()
        #expect(h.runner.scripts.isEmpty)
        let np = try #require(h.snapshots.first ?? nil)
        #expect(np.elapsed == 0)
        #expect(await h.session.send(.play) == false)
    }

    @Test func refreshAsksStateAndPosition() async throws {
        let h = SessionHarness()
        h.session.receive(.spotify, Payload.spotify("S"))
        await settle()
        h.runner.answer = { script in
            script.body == ScriptablePlayer.stateScript ? .value(ScriptValue(text: "Paused")) : .value(ScriptValue(number: 30))
        }
        h.session.refresh()
        h.session.refresh()                                  // a second request while one waits is the same request
        await settle()
        #expect(h.runner.bodies == [ScriptablePlayer.stateScript, position])
        let np = try #require(h.snapshots.last ?? nil)
        #expect(!np.isPlaying && np.rate == 0 && np.elapsed == 30)

        h.runner.answer = { _ in .value(ScriptValue(text: "stopped")) }
        h.session.refresh()
        await settle()
        #expect(h.snapshots.last == .some(nil))
    }

    @Test func stopAnswersWaitingCommandsAndDropsLateResults() async {
        let h = SessionHarness()
        h.runner.holds = true
        h.session.receive(.music, Payload.music("A"))
        await settle()
        let play = h.sendLater(.play)
        await settle()
        h.session.stop()
        await settle()
        #expect(play.value == false)
        h.runner.release(.value(ScriptValue(number: 5)))    // the script that was running when it stopped
        await settle()
        #expect(h.snapshots.isEmpty)
        #expect(h.finished)
        #expect(h.runner.bodies == [position])
        #expect(await h.session.send(.play) == false)
        h.session.receive(.music, Payload.music("B"))
        await settle()
        #expect(h.runner.bodies == [position])
    }
}

@Suite("Apple Events fallback: scripts") struct AppleScriptRunnerTests {
    @Test func scriptsRunOffTheMainThreadInSubmissionOrder() async {
        let log = OSAllocatedUnfairLock(initialState: [(body: String, onMain: Bool)]())
        let runner = SerialAppleScriptRunner(label: "test.applescript.order") { script in
            log.withLock { $0.append((script.body, Thread.isMainThread)) }
            return .value(ScriptValue(text: script.body))
        }
        let results = await MainActor.run {
            (0..<20).map { i in Task { @MainActor in await runner.run(PlayerScript(bundleID: "x", body: "\(i)")) } }
        }
        var answers: [ScriptOutcome] = []
        for task in results { answers.append(await task.value) }
        let entries = log.withLock { $0 }
        #expect(entries.map(\.body) == (0..<20).map(String.init))
        #expect(entries.allSatisfy { !$0.onMain })
        #expect(answers == (0..<20).map { .value(ScriptValue(text: "\($0)")) })
    }

    @Test @MainActor func aHungScriptDoesNotBlockTheMainActor() async {
        let gate = DispatchSemaphore(value: 0)
        let state = OSAllocatedUnfairLock(initialState: (started: false, finished: false, onMain: false))
        let runner = SerialAppleScriptRunner(label: "test.applescript.hang") { _ in
            state.withLock { $0.started = true; $0.onMain = Thread.isMainThread }
            _ = gate.wait(timeout: .now() + 5)              // a player that does not answer (bounded: no test hang)
            state.withLock { $0.finished = true }
            return .failed(code: -1712)
        }
        let task = Task { await runner.run(PlayerScript(bundleID: "x", body: "player position")) }
        #expect(await eventually { state.withLock { $0.started } })
        for _ in 0..<50 { await Task.yield() }              // the main actor keeps running while the script waits
        #expect(state.withLock { !$0.finished && !$0.onMain })
        gate.signal()
        #expect(await task.value == .failed(code: -1712))
    }

    @Test func aPlayerThatIsNotRunningGetsNoScript() {
        // No app has this identifier, so nothing is compiled or sent.
        let outcome = SerialAppleScriptRunner.runAppleScript(PlayerScript(bundleID: "app.cranny.tests.no-such-player", body: "play"))
        #expect(outcome == .notRunning)
    }

    @Test func sourceHasTheTimeoutAndNeverLaunchesThePlayer() {
        let source = PlayerScript(bundleID: "com.apple.Music", body: "player position").source
        #expect(source.hasPrefix("with timeout of 2 seconds\n"))
        #expect(source.contains(#"if not (application id "com.apple.Music" is running) then error number -600"#))
        #expect(source.contains(#"tell application id "com.apple.Music" to player position"#))
        #expect(source.hasSuffix("end timeout"))
    }

    @Test func resultsBecomeSendableValues() {
        #expect(ScriptValue(NSAppleEventDescriptor(string: "playing")) == ScriptValue(text: "playing"))
        #expect(ScriptValue(NSAppleEventDescriptor(double: 84.5)) == ScriptValue(number: 84.5))
        #expect(ScriptValue(NSAppleEventDescriptor(int32: 7)) == ScriptValue(number: 7))
        #expect(ScriptValue(NSAppleEventDescriptor.null()) == ScriptValue())
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let art = NSAppleEventDescriptor(descriptorType: 0x504E_4766, data: png)    // 'PNGf'
        #expect(art.map { ScriptValue($0) } == ScriptValue(binary: png))
        #expect(ScriptValue(NSAppleEventDescriptor(string: "12")).number == nil)     // text is never a number
    }

    @Test func commandScripts() {
        #expect(ScriptablePlayer.music.script(for: .togglePlayPause) == "playpause")
        #expect(ScriptablePlayer.music.script(for: .seek(to: 12.5)) == "set player position to 12.500")
        #expect(ScriptablePlayer.spotify.script(for: .seek(to: -3)) == "set player position to 0.000")
        #expect(ScriptablePlayer.music.script(for: .setShuffle(.tracks)) == "set shuffle enabled to true")
        #expect(ScriptablePlayer.spotify.script(for: .setShuffle(.off)) == "set shuffling to false")
        #expect(ScriptablePlayer.music.script(for: .setRepeat(.one)) == "set song repeat to one")
        #expect(ScriptablePlayer.spotify.script(for: .setRepeat(.all)) == "set repeating to true")
    }
}

@Suite("Apple Events fallback: declared players") @MainActor struct AutomationDeclarationTests {
    private func automationIDs(_ isInstalled: @escaping (String) -> Bool) -> [String] {
        let registry = ModuleRegistry(services: .preview())
        registry.registerMedia(isInstalled: isInstalled)
        return registry.permissionUses.compactMap { if case .automation(let id) = $0.kind { id } else { nil } }
    }

    @Test func onlyInstalledPlayersAskForAutomation() {
        #expect(automationIDs { _ in true } == ["com.apple.Music", "com.spotify.client"])
        #expect(automationIDs { $0 == "com.apple.Music" } == ["com.apple.Music"])
        #expect(automationIDs { _ in false } == [])
    }

    @Test func systemAudioRecordingIsDeclaredEitherWay() {
        let registry = ModuleRegistry(services: .preview())
        registry.registerMedia(isInstalled: { _ in false })
        #expect(registry.permissionUses.map(\.kind) == [.systemAudioRecording])
        #expect(registry.permissionUses.allSatisfy { $0.module == .media })
    }
}

private extension ModuleRegistry {
    /// `register(MediaModule.self)` with a fake installation check (attribution to `.media` included).
    func registerMedia(isInstalled: @escaping (String) -> Bool) {
        MediaWithFakeInstalls.isInstalled = isInstalled
        register(MediaWithFakeInstalls.self)
    }
}

/// Registers Media through the registry (so uses are attributed to the module) with a fake installation check.
@MainActor private enum MediaWithFakeInstalls: FeatureModule {
    static var isInstalled: (String) -> Bool = { _ in true }
    static var id: ModuleID { .media }
    static func register(in registry: ModuleRegistry) { MediaModule.register(in: registry, isInstalled: isInstalled) }
}
