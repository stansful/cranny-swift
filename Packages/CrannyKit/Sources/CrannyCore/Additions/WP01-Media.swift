// CrannyCore/Additions/WP01-Media.swift — additive Core change of WP1 Media (ARCHITECTURE.md §10.0).
import Foundation

/// Optional health facts of the `NowPlayingSource` for `--diagnostics` (ARCHITECTURE.md §6.5: the media source in
/// use, its state, the blocked-helper heuristic). The shell reads it with
/// `registry.services.nowPlaying as? any NowPlayingDiagnostics`; a source that does not conform reports nothing.
@MainActor public protocol NowPlayingDiagnostics: AnyObject {
    /// Stable keys and plain values ("media.provider": "perl"). Never track titles, artists or app names.
    var diagnostics: [String: String] { get }
}
