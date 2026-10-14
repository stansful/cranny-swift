// CrannyNotes/NotesModule.swift — the module's single entry point (ARCHITECTURE.md §3.4, §10.6): the Notes widget,
// the "notes" type-to-capture target, the New note shortcut, ⌘K commands, loading at launch and the final save at
// quit. `register(in:)` stays cheap: models and contributions only; the folder is read in `onLaunch`.
import CrannyCore
import Foundation

/// Notes: multiple notes with a code mode, in a 3–8-cell widget (DESIGN.md §7.5). Registered by the shell's
/// `CompositionRoot`. Storage: `AppPaths/notes/index.json` + `<uuid>.md`.
public enum NotesModule: FeatureModule {
    /// The module's settings namespace, storage folder and log category owner (`.notes`).
    public static var id: ModuleID { .notes }

    /// Registers the widget, the capture target, the shortcut and the commands; loads the notes at launch and
    /// writes pending edits synchronously at quit.
    public static func register(in registry: ModuleRegistry) {
        let services = registry.services
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        registry.add(widget: NotesWidget(model: model, settings: services.settings))
        registry.add(captureTarget: CaptureTarget(id: "notes", title: NotesStrings.notes, symbol: "note.text") { characters in
            model.capture(characters)
        })
        registry.add(shortcut: GlobalShortcut(id: .newNote, title: NotesStrings.newNote) { model.createAndReveal() })
        registry.add(commands: NotesCommands(model: model) {
            services.environment.isDemoMode && services.settings[CoreSettings.demoRedactsCalendar]
        })
        registry.onLaunch {
            services.notch.addEventObserver { event in
                if case .closed = event { model.panelClosed() }
            }
            await model.load()
            #if DEBUG
            NotesQAHooks.apply(to: model)
            #endif
        }
        registry.onTerminate { model.flush() }
    }
}
