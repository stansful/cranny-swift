// CrannyMedia/Service/MediaError.swift — what a user can see when media detection fails (ARCHITECTURE.md
// §9.3): localized one-liners, never raw NSError text.
import CrannyCore
import Foundation

enum MediaError: Error, LocalizedError, Equatable, Sendable {
    /// No provider could run (no helper, no interpreter, every provider failed three times).
    case noProvider
    /// A provider stopped; it is being restarted or replaced.
    case provider(MediaProviderKind, ProviderFailure)

    nonisolated var errorDescription: String? {
        switch self {
        case .noProvider:
            String(localized: "Cranny can't read what's playing right now.", bundle: .module,
                   comment: "Media: error line when no media source works (widget and Settings ▸ Media)")
        case .provider(_, .launchFailed):
            String(localized: "The media helper could not start.", bundle: .module,
                   comment: "Settings ▸ Media: last error, the perl/ruby helper could not be launched")
        case .provider(_, .noHandshake):
            String(localized: "The media helper did not respond.", bundle: .module,
                   comment: "Settings ▸ Media: last error, the helper never answered")
        case .provider(_, .exited):
            String(localized: "The media helper stopped unexpectedly.", bundle: .module,
                   comment: "Settings ▸ Media: last error, the helper process ended")
        case .provider(_, .notPermitted):
            String(localized: "Cranny isn't allowed to control this player.", bundle: .module,
                   comment: "Settings ▸ Media: last error, Automation permission denied")
        }
    }
}

/// The provider chain's state for Settings ▸ Media and the widget's loading/error states.
enum MediaProviderStatus: Equatable, Sendable {
    /// `start()` not called yet (or stopped).
    case idle
    /// A provider is launching (no snapshot yet).
    case starting(MediaProviderKind)
    /// A provider delivered at least one snapshot.
    case running(MediaProviderKind)
    /// The provider failed and restarts after a backoff.
    case restarting(MediaProviderKind)
    /// Every provider failed or none is available.
    case unavailable

    var kind: MediaProviderKind? {
        switch self {
        case .starting(let kind), .running(let kind), .restarting(let kind): kind
        case .idle, .unavailable: nil
        }
    }
}
