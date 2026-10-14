// CrannyMedia/Providers/AppleScriptProvider.swift — opt-in fallback for Music and Spotify when the MediaRemote
// helper is unavailable (ARCHITECTURE.md §6.5, R2 §5.2). Metadata comes from the players' distributed
// notifications (no permission); position, artwork and commands need Apple Events (Automation, per app).
//
// Rules: never launches a player (checks `runningApplications` first), never prompts by itself (scripts run
// only for players whose Automation status is granted), 2-s Apple Event timeout, no network (Spotify's
// artwork URL is not fetched: the update check is Cranny's only network access, §7.11).
// Threading: everything runs on the main actor (NSAppleScript is main-thread only); the provider façade
// hops there.
import AppKit
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.media)

nonisolated final class AppleScriptProvider: MediaProvider, @unchecked Sendable {   // immutable; state lives in `session`
    let kind = MediaProviderKind.appleScript
    let supportsCommands = true
    private let session: AppleScriptSession

    /// `isPermitted(bundleID)` = Automation granted for that player (asked from Settings ▸ Media).
    @MainActor init(isPermitted: @escaping @MainActor (String) -> Bool) {
        session = AppleScriptSession(isPermitted: isPermitted)
    }

    func start() -> AsyncStream<ProviderEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self, bufferingPolicy: .bufferingNewest(16))
        let session = session
        Task { @MainActor in session.start(continuation) }
        continuation.onTermination = { _ in Task { @MainActor in session.stop() } }
        return stream
    }

    func send(_ command: MediaCommand) async -> Bool {
        let session = session
        return await MainActor.run { session.send(command) }
    }

    func refresh() {
        let session = session
        Task { @MainActor in session.refresh() }
    }

    func ping() async -> Duration? { nil }

    func stop() {
        let session = session
        Task { @MainActor in session.stop() }
    }
}

/// A player reachable through Apple Events. Notification keys from R2 §5.2 (Music verified in the binary,
/// Spotify UNVERIFIED).
nonisolated struct ScriptablePlayer: Sendable, Equatable {
    let bundleID: String
    let notification: String
    /// `userInfo` key of the duration, in milliseconds for both players.
    let durationKey: String

    static let music = ScriptablePlayer(bundleID: "com.apple.Music", notification: "com.apple.Music.playerInfo", durationKey: "Total Time")
    static let spotify = ScriptablePlayer(bundleID: "com.spotify.client", notification: "com.spotify.client.PlaybackStateChanged", durationKey: "Duration")
    static let all = [music, spotify]

    /// The Now Playing snapshot of a notification payload; nil = stopped or untitled.
    func nowPlaying(_ info: [String: String], now: Date) -> NowPlaying? {
        let state = info["Player State"] ?? "Stopped"
        guard state != "Stopped", let title = info["Name"], !title.isEmpty else { return nil }
        var np = NowPlaying(bundleID: bundleID, title: title, artist: info["Artist"], album: info["Album"],
                            duration: info[durationKey].flatMap(Double.init).map { $0 / 1000 }.flatMap { $0 > 0 ? $0 : nil },
                            elapsed: info["Playback Position"].flatMap(Double.init) ?? 0, timestamp: now,
                            isPlaying: state == "Playing", itemID: info["PersistentID"] ?? info["Track ID"])
        np.isMusicApp = true
        return np
    }
}

@MainActor final class AppleScriptSession {
    private let isPermitted: @MainActor (String) -> Bool
    private var observers: [any NSObjectProtocol] = []
    private var current: ScriptablePlayer?
    /// The last snapshot sent, the base for `refresh()`.
    private var lastSnapshot: NowPlaying?
    private var continuation: AsyncStream<ProviderEvent>.Continuation?

    init(isPermitted: @escaping @MainActor (String) -> Bool) { self.isPermitted = isPermitted }

    func start(_ continuation: AsyncStream<ProviderEvent>.Continuation) {
        self.continuation = continuation
        let center = DistributedNotificationCenter.default()
        for player in ScriptablePlayer.all {
            observers.append(center.addObserver(forName: Notification.Name(player.notification), object: nil, queue: .main) { [weak self] note in
                // userInfo is not Sendable: copy the string values out before crossing into the actor.
                let info = (note.userInfo ?? [:]).reduce(into: [String: String]()) { out, pair in
                    if let key = pair.key as? String { out[key] = "\(pair.value)" }
                }
                MainActor.assumeIsolated { self?.handle(player, info) }    // queue: .main
            })
        }
        continuation.yield(.nowPlaying(nil))
    }

    func stop() {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers.removeAll()
        continuation?.finish()
        continuation = nil
    }

    func send(_ command: MediaCommand) -> Bool {
        guard let player = current else { return false }
        let music = player == .music
        let verb: String = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case .skipForward15: "set player position to (player position + 15)"
        case .skipBackward15: "set player position to (player position - 15)"
        case .seek(let t): "set player position to \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(t, 0)))"
        case .setShuffle(let m): music ? "set shuffle enabled to \(m != .off)" : "set shuffling to \(m != .off)"
        case .setRepeat(let m): music ? "set song repeat to \(m == .one ? "one" : m == .all ? "all" : "off")" : "set repeating to \(m != .off)"
        }
        return run(verb, in: player) != nil
    }

    /// After a command that no notification confirmed (`MediaService`): the player's state and position, asked
    /// directly. Nothing is sent when the scripts cannot run; the service then shows the last snapshot again.
    func refresh() {
        guard let player = current, var np = lastSnapshot,
              let state = run("player state as string", in: player)?.stringValue?.lowercased() else { return }
        guard state != "stopped" else {
            current = nil; lastSnapshot = nil
            continuation?.yield(.nowPlaying(nil))
            return
        }
        np.isPlaying = state == "playing"
        np.rate = np.isPlaying ? 1 : 0
        if let position = run("player position", in: player)?.doubleValue { np.elapsed = position }
        np.timestamp = Date()
        lastSnapshot = np
        continuation?.yield(.nowPlaying(np))
    }

    private func handle(_ player: ScriptablePlayer, _ info: [String: String]) {
        guard var np = player.nowPlaying(info, now: Date()) else {
            if current == player { current = nil; lastSnapshot = nil; continuation?.yield(.nowPlaying(nil)) }
            return
        }
        current = player
        if let position = run("player position", in: player)?.doubleValue {
            np.elapsed = position
            np.timestamp = Date()
        }
        lastSnapshot = np
        continuation?.yield(.nowPlaying(np))
        if player == .music, let art = run("get raw data of artwork 1 of current track", in: player),
           art.descriptorType != typeUnicodeText, art.descriptorType != typeUTF8Text, !art.data.isEmpty {
            continuation?.yield(.artwork(trackKey: np.trackKey, data: art.data))
        }
    }

    /// NSAppleScript with a 2-s timeout; only for a running player whose Automation is granted.
    private func run(_ body: String, in player: ScriptablePlayer) -> NSAppleEventDescriptor? {
        guard isPermitted(player.bundleID),
              !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty else { return nil }
        let source = "with timeout of 2 seconds\ntell application id \"\(player.bundleID)\" to \(body)\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // −1743 (errAEEventNotPermitted): the user denied Automation; Settings ▸ Media shows it.
            log.error("Apple Events to \(player.bundleID, privacy: .public) failed: \(error[NSAppleScript.errorNumber] as? Int ?? 0, privacy: .public)")
            return nil
        }
        return result
    }
}
