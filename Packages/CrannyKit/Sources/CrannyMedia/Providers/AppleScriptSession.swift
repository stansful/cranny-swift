// CrannyMedia/Providers/AppleScriptSession.swift — the Apple Events fallback's state and its ordered work queue
// (ARCHITECTURE.md §6.5).
//
// Threading: everything here is on the main actor, and none of it blocks: the scripts run on
// `SerialAppleScriptRunner`'s queue and the session awaits them. Notifications, commands and refreshes become jobs
// that one worker task performs strictly one after another, in arrival order, so events reach the service in the
// order the player caused them (a slow script for one notification is never overtaken by the next). While a job
// waits, a newer notification of the same player replaces the one still waiting (each is a full snapshot), and a
// command that waited longer than the scripts' own 2-s timeout is not sent at all (it answers false, so the service
// shows the player's state again).
//
// Automation: `isPermitted` is a synchronous TCC query on the main actor (`PermissionsCenter.status`, which never
// prompts and does not keep Automation answers). A granted answer is used for `grantLifetime`, so a burst of
// scripts (position + artwork, a command + its refresh) asks once instead of once per script. Any failed script
// forgets it (a −1743 denial included), and a player that is not granted is asked again before each script, so a
// grant from Settings ▸ Media counts at once. No script runs for a player last found not granted. A grant turned
// off in System Settings within the window costs one script that fails with −1743 (no prompt; reported as usual);
// only a reset of the decision (`tccutil reset AppleEvents`) within those 30 s could let macOS ask.
import AppKit
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

@MainActor final class AppleScriptSession {
    /// −1743 (errAEEventNotPermitted): the user turned Automation off for this player.
    static let notPermitted = -1743
    /// A command still waiting after this long is dropped instead of sent late (the scripts' Apple Event timeout).
    static let commandDeadline: Duration = .seconds(2)
    /// How long a granted Automation answer is used before `isPermitted` is asked again (see the file header).
    static let grantLifetime: Duration = .seconds(30)

    private enum Job {
        case notification(ScriptablePlayer, [String: String], received: Date)
        case command(MediaCommand, queued: Date, reply: CheckedContinuation<Bool, Never>)
        case refresh
    }

    private let isPermitted: @MainActor (String) -> Bool
    private let runner: any AppleScriptRunning
    private let clock: any MediaClock
    /// False in tests: they feed payloads to `receive` and never hear the user's real players.
    private let observesPlayers: Bool
    private var observers: [any NSObjectProtocol] = []
    private var current: ScriptablePlayer?
    /// The last snapshot sent, the base for `refresh()`.
    private var lastSnapshot: NowPlaying?
    /// The track whose artwork was fetched last (Music re-posts `playerInfo` on play, pause and seek).
    private var lastArtworkKey: String?
    /// Players already reported as denied (one event each).
    private var reportedDenied: Set<String> = []
    /// When each player's Automation was last found granted (`isAllowed`); a failed script removes its entry.
    private var grantedAt: [String: Date] = [:]
    private var continuation: AsyncStream<ProviderEvent>.Continuation?
    private var jobs: [Job] = []
    /// Performs `jobs` one at a time; nil while there is nothing to do.
    private var worker: Task<Void, Never>?
    /// A session runs once: after `stop()` nothing starts, runs or reaches the service again.
    private var isStopped = false

    init(isPermitted: @escaping @MainActor (String) -> Bool, runner: any AppleScriptRunning,
         clock: any MediaClock = SystemMediaClock(), observesPlayers: Bool = true) {
        self.isPermitted = isPermitted
        self.runner = runner
        self.clock = clock
        self.observesPlayers = observesPlayers
    }

    // MARK: Lifecycle

    func start(_ continuation: AsyncStream<ProviderEvent>.Continuation) {
        guard !isStopped else { continuation.finish(); return }
        self.continuation = continuation
        if observesPlayers { observePlayers() }
        continuation.yield(.nowPlaying(nil))
    }

    private func observePlayers() {
        let center = DistributedNotificationCenter.default()
        for player in ScriptablePlayer.all {
            observers.append(center.addObserver(forName: Notification.Name(player.notification), object: nil, queue: .main) { [weak self] note in
                // userInfo is not Sendable: copy the string values out before crossing into the actor.
                let info = (note.userInfo ?? [:]).reduce(into: [String: String]()) { out, pair in
                    if let key = pair.key as? String { out[key] = "\(pair.value)" }
                }
                MainActor.assumeIsolated { self?.receive(player, info) }    // queue: .main
            })
        }
    }

    /// Stops observing, answers every waiting command with false and finishes the stream. A script already running
    /// finishes on its queue; its result is dropped.
    func stop() {
        isStopped = true
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers.removeAll()
        worker?.cancel()
        for case .command(_, _, let reply) in jobs { reply.resume(returning: false) }
        jobs.removeAll()
        continuation?.finish()
        continuation = nil
    }

    // MARK: Inputs (in arrival order)

    /// A player's notification payload (the observer; tests call it directly).
    func receive(_ player: ScriptablePlayer, _ info: [String: String]) {
        enqueue(.notification(player, info, received: clock.now))
    }

    /// Sends `command` to the current player after the work already queued. True when its script ran.
    func send(_ command: MediaCommand) async -> Bool {
        guard !isStopped else { return false }
        return await withCheckedContinuation { reply in
            enqueue(.command(command, queued: clock.now, reply: reply))
        }
    }

    /// After a command that no notification confirmed (`MediaService`): the player's state and position, asked
    /// directly. Nothing is sent when the scripts cannot run; the service then shows the last snapshot again.
    func refresh() {
        enqueue(.refresh)
    }

    // MARK: The queue

    private func enqueue(_ job: Job) {
        guard !isStopped else {
            if case .command(_, _, let reply) = job { reply.resume(returning: false) }
            return
        }
        switch (job, jobs.last) {
        case (.notification(let player, _, _), .notification(let waiting, _, _)?) where waiting == player:
            jobs[jobs.count - 1] = job                      // a newer full snapshot of the same player
        case (.refresh, .refresh?):
            return
        default:
            jobs.append(job)
        }
        if worker == nil { worker = Task { await self.drain() } }
    }

    private func drain() async {
        while !isStopped, !Task.isCancelled, !jobs.isEmpty {
            await perform(jobs.removeFirst())
        }
        worker = nil
    }

    private func perform(_ job: Job) async {
        switch job {
        case .notification(let player, let info, let received):
            await handle(player, info, received: received)
        case .command(let command, let queued, let reply):
            reply.resume(returning: await execute(command, queued: queued))
        case .refresh:
            await refreshState()
        }
    }

    // MARK: Jobs

    private func handle(_ player: ScriptablePlayer, _ info: [String: String], received: Date) async {
        guard var np = player.nowPlaying(info, now: received) else {
            if current == player { current = nil; lastSnapshot = nil; yield(.nowPlaying(nil)) }
            return
        }
        current = player
        if !player.reportsPosition(info), let position = await run(ScriptablePlayer.positionScript, in: player)?.number {
            np.elapsed = position
            np.timestamp = clock.now
        }
        guard !isStopped else { return }
        lastSnapshot = np
        yield(.nowPlaying(np))
        guard player == .music, np.trackKey != lastArtworkKey else { return }
        lastArtworkKey = np.trackKey                                     // once per track, even without artwork
        if let art = await run(ScriptablePlayer.artworkScript, in: player)?.binary {
            yield(.artwork(trackKey: np.trackKey, data: art))
        }
    }

    private func execute(_ command: MediaCommand, queued: Date) async -> Bool {
        guard let player = current else { return false }
        guard clock.now.timeIntervalSince(queued) <= Self.commandDeadline.timeInterval else {
            log.info("Apple Events: a command waited too long behind a slow player; not sent")
            return false
        }
        return await run(player.script(for: command), in: player) != nil
    }

    private func refreshState() async {
        guard let player = current, lastSnapshot != nil,
              let state = await run(ScriptablePlayer.stateScript, in: player)?.text?.lowercased(),
              var np = lastSnapshot else { return }
        guard state != "stopped" else {
            current = nil; lastSnapshot = nil
            yield(.nowPlaying(nil))
            return
        }
        np.isPlaying = state == "playing"
        np.rate = np.isPlaying ? 1 : 0
        if let position = await run(ScriptablePlayer.positionScript, in: player)?.number { np.elapsed = position }
        guard !isStopped else { return }
        np.timestamp = clock.now
        lastSnapshot = np
        yield(.nowPlaying(np))
    }

    // MARK: Scripts

    /// Runs `body` for a player whose Automation is granted, off the main actor. nil = not run, failed, or the
    /// session stopped meanwhile.
    private func run(_ body: String, in player: ScriptablePlayer) async -> ScriptValue? {
        guard !isStopped, isAllowed(player) else { return nil }
        let outcome = await runner.run(PlayerScript(bundleID: player.bundleID, body: body))
        guard !isStopped else { return nil }
        switch outcome {
        case .value(let value):
            return value
        case .notRunning:
            return nil
        case .failed(let code):
            grantedAt[player.bundleID] = nil                             // the next script asks again
            log.error("Apple Events to \(player.bundleID, privacy: .public) failed: \(code, privacy: .public)")
            // The service records a denial (Settings ▸ Media and Permissions show it), and no further script runs
            // for that player.
            if code == Self.notPermitted, reportedDenied.insert(player.bundleID).inserted {
                yield(.permissionDenied(bundleID: player.bundleID))
            }
            return nil
        }
    }

    /// Automation is granted for `player`: a grant found less than `grantLifetime` ago, else `isPermitted` (a TCC
    /// query on the main actor). A clock that went backwards does not stretch a grant.
    private func isAllowed(_ player: ScriptablePlayer) -> Bool {
        let id = player.bundleID
        if let since = grantedAt[id], (0..<Self.grantLifetime.timeInterval).contains(clock.now.timeIntervalSince(since)) {
            return true
        }
        guard isPermitted(id) else { grantedAt[id] = nil; return false }
        grantedAt[id] = clock.now
        return true
    }

    private func yield(_ event: ProviderEvent) {
        continuation?.yield(event)
    }
}
