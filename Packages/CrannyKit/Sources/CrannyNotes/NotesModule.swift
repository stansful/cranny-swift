// CrannyNotes/NotesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP5 (Notes) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum NotesModule: FeatureModule {
    public static var id: ModuleID { .notes }
    public static func register(in registry: ModuleRegistry) {
        // WP5: the Notes widget, the "notes" capture target, `.newNote` shortcut, ⌘K commands.
    }
}
