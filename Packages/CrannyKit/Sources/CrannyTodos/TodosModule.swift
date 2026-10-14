// CrannyTodos/TodosModule.swift — the module's single entry point (ARCHITECTURE.md §3.4).
// Placeholder from WP0: WP6 (To-dos) grows it. Keep `register(in:)` cheap — models + contributions only;
// file I/O, hardware, prompts and processes start in `registry.onLaunch`.
import CrannyCore

public enum TodosModule: FeatureModule {
    public static var id: ModuleID { .todos }
    public static func register(in registry: ModuleRegistry) {
        // WP6: the To-dos widget and the "todos" capture target.
    }
}
