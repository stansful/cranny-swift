// CrannyHUD/HUDModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP9 (HUD) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// HUD: volume, brightness and keyboard backlight (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum HUDModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.hud`).
    public static var id: ModuleID { .hud }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP9: the HUD activity and Settings ▸ HUD; declare `.accessibility`.
    }
}
