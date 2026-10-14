// CrannyMirror/MirrorModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP4 (Mirror) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Mirror: the camera preview widget (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum MirrorModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.mirror`).
    public static var id: ModuleID { .mirror }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP4: the frameless camera widget; declare `.camera`.
    }
}
