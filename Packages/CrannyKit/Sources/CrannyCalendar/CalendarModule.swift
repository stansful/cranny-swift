// CrannyCalendar/CalendarModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP2 (Calendar) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum CalendarModule: FeatureModule {
    public static var id: ModuleID { .calendar }
    public static func register(in registry: ModuleRegistry) {
        // WP2: the Calendar widget, Meeting soon / in progress activities, Settings ▸ Calendar.
    }
}
