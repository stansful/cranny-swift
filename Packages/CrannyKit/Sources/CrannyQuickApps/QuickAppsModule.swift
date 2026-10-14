// CrannyQuickApps/QuickAppsModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP3 (Quick Apps & Shortcuts) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Quick Apps & Shortcuts: app and Shortcuts.app launchers (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum QuickAppsModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.quickApps`).
    public static var id: ModuleID { .quickApps }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP3: the launcher widget, Settings ▸ Shortcuts, ⌘K launch commands.
    }
}
