// CrannyMedia/Providers/MediaRemoteBridgeProvider.swift — the primary provider: system-wide Now Playing via
// MediaRemote, reached through an Apple-signed interpreter, because mediaremoted refuses unentitled clients
// since macOS 15.4 (ARCHITECTURE.md §6.1, R2). Never polls: the helper pushes state on MR notifications.
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.mediaBridge)

nonisolated final class MediaRemoteBridgeProvider: MediaProvider, @unchecked Sendable {   // state behind `lock`
    let kind: MediaProviderKind
    let supportsCommands = true

    private let host: BridgeConnection.Host
    private let dylib: URL
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var connection: BridgeConnection?
        var lastTrackKey: String?
    }

    /// `dylib` from `BridgeLocator`; the factory checks that the interpreter exists.
    init(host: BridgeConnection.Host, dylib: URL) {
        self.host = host
        self.dylib = dylib
        kind = host == .perl ? .perl : .ruby
    }

    func start() -> AsyncStream<ProviderEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self, bufferingPolicy: .bufferingNewest(32))
        let connection = BridgeConnection(
            host: host, dylib: dylib,
            onMessage: { [weak self] message in
                guard let self else { return }
                for event in self.events(for: message, at: Date()) { continuation.yield(event) }
            },
            onEnd: { failure in
                continuation.yield(.unavailable(failure))
                continuation.finish()
            })
        lock.withLock { $0.connection = connection; $0.lastTrackKey = nil }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        do {
            try connection.start()
        } catch {
            continuation.yield(.unavailable(.launchFailed(error.localizedDescription)))
            continuation.finish()
        }
        return stream
    }

    /// Waits for the helper's `ack` (≈ 12 ms): `ok:false` means MediaRemote did not take the command (no player to
    /// receive it); no answer within a second counts as not delivered.
    func send(_ command: MediaCommand) async -> Bool {
        guard let connection = lock.withLock({ $0.connection }) else { return false }
        switch await connection.command(Self.line(for: command)) {
        case true?: return true
        case false?: log.info("bridge: MediaRemote refused a command"); return false
        case nil: return false
        }
    }

    /// `refresh state`: the helper forgets its last snapshot and sends the current one again (not the artwork).
    func refresh() {
        lock.withLock { $0.connection }?.send(Self.refreshLine)
    }

    static let refreshLine = "refresh state"

    func ping() async -> Duration? {
        guard let connection = lock.withLock({ $0.connection }) else { return nil }
        return await connection.ping()
    }

    func stop() {
        let connection = lock.withLock { state -> BridgeConnection? in
            defer { state.connection = nil }
            return state.connection
        }
        connection?.close()
    }

    /// App termination: the helper must be gone before Cranny exits.
    func terminateNow() {
        let connection = lock.withLock { state -> BridgeConnection? in
            defer { state.connection = nil }
            return state.connection
        }
        connection?.terminateNow()
    }

    // MARK: - Protocol mapping (pure)

    /// The bridge's stdin command for a Core command (MRMediaRemoteSendCommand ids, R2 §3).
    static func line(for command: MediaCommand) -> String {
        switch command {
        case .play: "cmd 0"
        case .pause: "cmd 1"
        case .togglePlayPause: "cmd 2"
        case .nextTrack: "cmd 4"
        case .previousTrack: "cmd 5"
        case .skipBackward15: "cmd 12"
        case .skipForward15: "cmd 13"
        case .seek(let seconds): "seek " + String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds.isFinite ? seconds : 0))
        case .setShuffle(let mode): "shuffle \(mode.rawValue)"
        case .setRepeat(let mode): "repeat \(mode.rawValue)"
        }
    }

    /// Provider events for one bridge message. Artwork without an item id belongs to the last state's track.
    func events(for message: BridgeMessage, at now: Date) -> [ProviderEvent] {
        switch message {
        case .state(let state):
            let np = state.nowPlaying(receivedAt: now)
            lock.withLock { $0.lastTrackKey = np?.trackKey }
            return [.nowPlaying(np)]
        case .artwork(let itemID, let data):
            guard let key = itemID ?? lock.withLock({ $0.lastTrackKey }) else { return [] }
            return [.artwork(trackKey: key, data: data)]
        case .hello, .pong, .ack, .error:
            return []     // answers to pings and commands are matched by the connection
        }
    }
}
