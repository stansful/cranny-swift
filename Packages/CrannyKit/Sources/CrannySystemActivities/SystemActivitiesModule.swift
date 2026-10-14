// CrannySystemActivities/SystemActivitiesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP10 (System activities) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// System activities: battery, charging and Bluetooth accessories (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum SystemActivitiesModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.system`).
    public static var id: ModuleID { .system }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP10: Charging, Low battery and Bluetooth device activities.
    }
}
