// CrannyMedia/MediaModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP1 (Media) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Media: Now Playing, the Media widget and the media bridge client (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum MediaModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.media`).
    public static var id: ModuleID { .media }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP1: publish `registry.services.nowPlaying` (MediaService), then the Media widget, the Now Playing activity, Settings ▸ Media, ⌘K commands and permission uses.
    }
}
