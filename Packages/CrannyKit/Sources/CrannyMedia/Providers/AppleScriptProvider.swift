// CrannyMedia/Providers/AppleScriptProvider.swift — opt-in fallback for Music and Spotify when the MediaRemote
// helper is unavailable (ARCHITECTURE.md §6.5, R2 §5.2). Metadata comes from the players' distributed
// notifications (no permission); position, artwork and commands need Apple Events (Automation, per app).
//
// Rules: never launches a player (checks `runningApplications` first, and every script re-checks), never prompts by
// itself (scripts run only for players whose Automation status is granted), 2-s Apple Event timeout, no network
// (Spotify's artwork URL is not fetched: the update check is Cranny's only network access, §7.11). A denial (−1743)
// is reported as `.permissionDenied`, and the service records it in `PermissionsCenter`. Scripts per notification:
// the position only when the payload lacks it (Music), the artwork only when the track changes.
// Threading: the session's state lives on the main actor; the scripts run off it, one at a time, on
// `SerialAppleScriptRunner`'s queue (AppleScriptRunner.swift), and the session awaits them in order
// (AppleScriptSession.swift). The provider façade is nonisolated and hops to the main actor.
import AppKit
import CrannyCore
import Foundation

nonisolated final class AppleScriptProvider: MediaProvider, @unchecked Sendable {   // immutable; state lives in `session`
    let kind = MediaProviderKind.appleScript
    let supportsCommands = true
    private let session: AppleScriptSession

    /// `isPermitted(bundleID)` = Automation granted for that player (asked from Settings ▸ Media). `runner` executes
    /// the scripts (the process-wide serial runner; tests pass a fake).
    @MainActor init(isPermitted: @escaping @MainActor (String) -> Bool,
                    runner: any AppleScriptRunning = SerialAppleScriptRunner.shared) {
        session = AppleScriptSession(isPermitted: isPermitted, runner: runner)
    }

    func start() -> AsyncStream<ProviderEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self, bufferingPolicy: .bufferingNewest(16))
        let session = session
        Task { @MainActor in session.start(continuation) }
        continuation.onTermination = { _ in Task { @MainActor in session.stop() } }
        return stream
    }

    func send(_ command: MediaCommand) async -> Bool {
        await session.send(command)
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

    /// The players installed on this Mac, in `all` order (Settings ▸ Permissions and onboarding list Automation only
    /// for these). `isInstalled` is a Launch Services lookup in the app.
    static func installed(_ isInstalled: (String) -> Bool = ScriptablePlayer.isInstalled) -> [ScriptablePlayer] {
        all.filter { isInstalled($0.bundleID) }
    }

    /// Launch Services knows an app with this bundle identifier (wherever it is; nothing in it is read).
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Spotify's payload carries the position; Music's does not (it needs a `player position` script).
    func reportsPosition(_ info: [String: String]) -> Bool { info["Playback Position"].flatMap(Double.init) != nil }

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

    /// What to tell the player for `command` (Music and Spotify name shuffle and repeat differently).
    func script(for command: MediaCommand) -> String {
        let music = self == .music
        return switch command {
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
    }

    /// Music's artwork of the current track (raw image data; `ScriptValue.binary`).
    static let artworkScript = "get raw data of artwork 1 of current track"
    static let positionScript = "player position"
    static let stateScript = "player state as string"
}
