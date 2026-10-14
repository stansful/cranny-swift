// CrannyMedia/Providers/MediaProvider.swift — the module-internal provider contract (ARCHITECTURE.md §6.4).
// Providers are `nonisolated` and Sendable: they own helper processes, pipes and notification observers on
// their own queues and talk to `MediaService` (main actor) through an `AsyncStream` of `ProviderEvent`s.
import CrannyCore
import Foundation

/// Which source a provider reads. Raw values are stable (diagnostics, logs).
nonisolated enum MediaProviderKind: String, Sendable, CaseIterable {
    /// MediaRemote through our bridge dylib hosted by `/usr/bin/perl` (primary).
    case perl
    /// The same bridge hosted by `/usr/bin/ruby` (Fiddle).
    case ruby
    /// Music and Spotify through distributed notifications + Apple Events (opt-in).
    case appleScript
    /// A fixed session for previews, stages and Debug visual QA. Never touches the system.
    case sample
}

/// Why a provider stopped. The service restarts it with backoff or moves to the next one.
nonisolated enum ProviderFailure: Error, Equatable, Sendable {
    /// The interpreter could not be launched.
    case launchFailed(String)
    /// The helper ran but never said hello (missing symbols, a Gatekeeper prompt, a blocked dylib).
    case noHandshake
    /// The helper exited (crash, `kill -9`, unknown exit status).
    case exited(status: Int32)
    /// The user denied Automation for the player (Apple Events error −1743).
    case notPermitted

    /// The failure's kind for logs and diagnostics: never the launch error's text, which can contain paths.
    var logName: String {
        switch self {
        case .launchFailed: "launchFailed"
        case .noHandshake: "noHandshake"
        case .exited(let status): "exited(\(status))"
        case .notPermitted: "notPermitted"
        }
    }
}

/// What a provider reports.
nonisolated enum ProviderEvent: Sendable, Equatable {
    /// A full snapshot; nil = nothing playing (no session, or a session without a title).
    case nowPlaying(NowPlaying?)
    /// Encoded artwork (JPEG/PNG/HEIC) for `trackKey` (`NowPlaying.trackKey`).
    case artwork(trackKey: String, data: Data)
    /// The provider stopped working; the stream finishes right after this event.
    case unavailable(ProviderFailure)
}

/// One source of now-playing data and transport control.
nonisolated protocol MediaProvider: AnyObject, Sendable {
    var kind: MediaProviderKind { get }
    /// Whether `send` can reach the player (false = show title only, no transport).
    var supportsCommands: Bool { get }
    /// Starts the provider. The stream finishes after `.unavailable` or `stop()`.
    func start() -> AsyncStream<ProviderEvent>
    /// Sends a transport command. Returns true only when the player side accepted it (the bridge's `ack ok`,
    /// a script that ran); false when it was refused, could not be delivered or was not answered in time.
    @discardableResult func send(_ command: MediaCommand) async -> Bool
    /// Asks for the current state again, even when it did not change (the service's check after a command
    /// that no state confirmed). The answer, if any, arrives as an ordinary `.nowPlaying` event.
    func refresh()
    /// Round trip to the helper for "Test media detection"; nil = no answer within the timeout.
    func ping() async -> Duration?
    /// Stops the provider and its helper. Safe to call more than once.
    func stop()
}

extension MediaProviderKind {
    /// Localized name for Settings ▸ Media ("Source status") and diagnostics.
    var title: String {
        switch self {
        case .perl:
            String(localized: "MediaRemote helper (perl)", bundle: .module, comment: "Settings ▸ Media: name of the media source in use")
        case .ruby:
            String(localized: "MediaRemote helper (ruby)", bundle: .module, comment: "Settings ▸ Media: name of the media source in use")
        case .appleScript:
            String(localized: "Apple Events (Music, Spotify)", bundle: .module, comment: "Settings ▸ Media: name of the media source in use")
        case .sample:
            String(localized: "Sample track", bundle: .module, comment: "Settings ▸ Media: name of the media source in previews")
        }
    }
}
