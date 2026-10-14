// CrannyHUD/HUDModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP9 (HUD) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum HUDModule: FeatureModule {
    public static var id: ModuleID { .hud }
    public static func register(in registry: ModuleRegistry) {
        // WP9: the HUD activity and Settings ▸ HUD; declare `.accessibility`.
    }
}
