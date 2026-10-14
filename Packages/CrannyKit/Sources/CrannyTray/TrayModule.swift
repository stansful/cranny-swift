// CrannyTray/TrayModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP8 (Tray, AirDrop, Files) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum TrayModule: FeatureModule {
    public static var id: ModuleID { .tray }
    public static func register(in registry: ModuleRegistry) {
        // WP8: publish `registry.services.tray` (TrayIntake), the Tray page, AirDrop and Files widgets, Settings ▸ Tray.
    }
}
