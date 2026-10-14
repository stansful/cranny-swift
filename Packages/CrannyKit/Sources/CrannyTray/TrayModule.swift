// CrannyTray/TrayModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP8 (Tray, AirDrop, Files) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Tray: dropped files, AirDrop and pipelines (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum TrayModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.tray`).
    public static var id: ModuleID { .tray }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP8: publish `registry.services.tray` (TrayIntake), the Tray page, AirDrop and Files widgets, Settings ▸ Tray.
    }
}
