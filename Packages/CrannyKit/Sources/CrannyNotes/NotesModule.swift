// CrannyNotes/NotesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP5 (Notes) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// Notes: the Notes widget and its store (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum NotesModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.notes`).
    public static var id: ModuleID { .notes }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP5: the Notes widget, the "notes" capture target, `.newNote` shortcut, ⌘K commands.
    }
}
