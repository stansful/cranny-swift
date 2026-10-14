// CrannySystemActivities/SystemActivitiesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP10 (System activities) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum SystemActivitiesModule: FeatureModule {
    public static var id: ModuleID { .system }
    public static func register(in registry: ModuleRegistry) {
        // WP10: Charging, Low battery and Bluetooth device activities.
    }
}
