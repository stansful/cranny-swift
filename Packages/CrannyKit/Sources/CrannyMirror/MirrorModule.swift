// CrannyMirror/MirrorModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP4 (Mirror) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum MirrorModule: FeatureModule {
    public static var id: ModuleID { .mirror }
    public static func register(in registry: ModuleRegistry) {
        // WP4: the frameless camera widget; declare `.camera`.
    }
}
