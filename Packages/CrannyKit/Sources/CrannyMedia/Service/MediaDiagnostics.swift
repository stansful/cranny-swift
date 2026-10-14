// CrannyMedia/Service/MediaDiagnostics.swift — what `--diagnostics` reports about media (ARCHITECTURE.md §6.5):
// the provider in use, its state, the last error kind, the blocked-helper flag and the visualizer mode. No titles,
// artists or app names (diagnostics are shared in bug reports).
import CrannyCore
import Foundation

extension MediaService: NowPlayingDiagnostics {
    var diagnostics: [String: String] {
        [
            "media.provider": status.kind?.rawValue ?? "none",
            "media.status": Self.name(of: status),
            "media.lastError": lastError.map(Self.name(of:)) ?? "none",
            "media.degraded": String(health?.isDegraded ?? false),
            "media.outputActive": String(health?.isOutputActive ?? false),
            "media.session": nowPlaying == nil ? "none" : (nowPlaying?.isPlaying == true ? "playing" : "paused"),
            "media.visualizer": visualizer.mode.rawValue,
            "media.live": String(describing: visualizer.liveStatus),
        ]
    }

    private static func name(of status: MediaProviderStatus) -> String {
        switch status {
        case .idle: "idle"
        case .starting: "starting"
        case .running: "running"
        case .restarting: "restarting"
        case .unavailable: "unavailable"
        }
    }

    private static func name(of error: MediaError) -> String {
        switch error {
        case .noProvider: "noProvider"
        case .provider(let kind, .launchFailed): "\(kind.rawValue).launchFailed"
        case .provider(let kind, .noHandshake): "\(kind.rawValue).noHandshake"
        case .provider(let kind, .exited(let status)): "\(kind.rawValue).exited(\(status))"
        case .provider(let kind, .notPermitted): "\(kind.rawValue).notPermitted"
        }
    }
}
