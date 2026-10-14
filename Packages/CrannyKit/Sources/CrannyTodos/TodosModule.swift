// CrannyTodos/TodosModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP6 (To-dos) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

/// To-dos: the To-dos widget and its store (ARCHITECTURE.md §3.4). Registered by the shell's `CompositionRoot`.
public enum TodosModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.todos`).
    public static var id: ModuleID { .todos }
    /// Registers the module's contributions; cheap — I/O, hardware and prompts start in `registry.onLaunch`.
    public static func register(in registry: ModuleRegistry) {
        // WP6: the To-dos widget and the "todos" capture target.
    }
}
