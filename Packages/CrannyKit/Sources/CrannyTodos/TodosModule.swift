// CrannyTodos/TodosModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §10.7): the To-dos
// widget, its ⌘K commands and the "todos" type-to-capture target. `register(in:)` only creates the model and
// contributes; the list is read in `onLaunch` (off the main actor) and flushed in `onTerminate`.
import CrannyCore

/// To-dos: a short checklist in the open Cranny panel, stored in `AppPaths/todos/todos.json`.
/// Registered by the shell's `CompositionRoot`.
public enum TodosModule: FeatureModule {
    /// The module's settings namespace and owner tag (`.todos`).
    public static var id: ModuleID { .todos }

    /// `CaptureTarget.id` of To-dos (the value of `CoreSettings.typeToCapture` that routes typing here).
    public static let captureTargetID = "todos"

    /// Registers the widget, the ⌘K provider and the capture target. Cheap: no I/O, no prompts, no hardware.
    public static func register(in registry: ModuleRegistry) {
        let model = TodosModel(services: registry.services)
        registry.add(widget: TodosWidget(model: model))
        registry.add(commands: TodosCommands(model: model))
        registry.add(captureTarget: CaptureTarget(id: captureTargetID, title: TodosStrings.title, symbol: "checklist") { text in
            model.capture(text)
        })
        registry.onLaunch { await model.start() }
        registry.onTerminate { model.flush() }
    }
}
