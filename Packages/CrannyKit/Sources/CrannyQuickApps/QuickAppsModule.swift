// CrannyQuickApps/QuickAppsModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP3 (Quick Apps & Shortcuts) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum QuickAppsModule: FeatureModule {
    public static var id: ModuleID { .quickApps }
    public static func register(in registry: ModuleRegistry) {
        // WP3: the launcher widget, Settings ▸ Shortcuts, ⌘K launch commands.
    }
}
