// CrannyMedia/MediaModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP1 (Media) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum MediaModule: FeatureModule {
    public static var id: ModuleID { .media }
    public static func register(in registry: ModuleRegistry) {
        // WP1: publish `registry.services.nowPlaying` (MediaService), then the Media widget, the Now Playing activity, Settings ▸ Media, ⌘K commands and permission uses.
    }
}
