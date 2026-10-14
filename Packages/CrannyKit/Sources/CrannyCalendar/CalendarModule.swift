// CrannyCalendar/CalendarModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP2 (Calendar) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Calendar: upcoming events, meeting activities and the Calendar widget (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum CalendarModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.calendar`).
    public static var id: ModuleID { .calendar }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP2: the Calendar widget, Meeting soon / in progress activities, Settings ▸ Calendar.
    }
}
