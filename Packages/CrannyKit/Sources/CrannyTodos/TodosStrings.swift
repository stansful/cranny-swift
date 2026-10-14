// CrannyTodos/TodosStrings.swift — every user-visible string of the module, in one place so each catalog key
// has exactly one translator comment ("<Surface>: <purpose>", ARCHITECTURE.md §8.7, §10.0). Copy is original
// and follows DESIGN.md §17 (calm, sentence case, no exclamation marks).
import Foundation

nonisolated enum TodosStrings {
    /// The module's resources (tests read the Russian catalog through it).
    static var bundle: Bundle { .module }

    // MARK: Names

    static var title: String {
        String(localized: "To-dos", bundle: .module,
               comment: "To-dos: module name (widget title, widget header, type-to-capture target, ⌘K result kind)")
    }
    static var summary: String {
        String(localized: "A short list of things to do", bundle: .module, comment: "Widget library: To-dos description")
    }

    // MARK: Widget

    static func remaining(_ count: Int) -> String {
        String(localized: "\(count) left", bundle: .module, comment: "To-dos widget: header count of unfinished to-dos")
    }
    static var allDone: String {
        String(localized: "All done", bundle: .module,
               comment: "To-dos widget: header count and empty state when every to-do is checked")
    }
    static var noTodos: String {
        String(localized: "No to-dos yet", bundle: .module, comment: "To-dos widget: empty state message")
    }
    static var newTodo: String {
        String(localized: "New to-do", bundle: .module,
               comment: "To-dos: the trailing “New to-do” row, its placeholder text, the empty-state action and the ⌘K command")
    }

    // MARK: Actions (context menu, VoiceOver actions, Undo)

    static var edit: String {
        String(localized: "Edit", bundle: .module, comment: "To-dos widget: context menu item and VoiceOver action that edits a to-do")
    }
    static var markDone: String {
        String(localized: "Mark as done", bundle: .module, comment: "To-dos widget: context menu item")
    }
    static var markNotDone: String {
        String(localized: "Mark as not done", bundle: .module, comment: "To-dos widget: context menu item")
    }
    static var moveUp: String {
        String(localized: "Move up", bundle: .module, comment: "To-dos widget: context menu item and VoiceOver action")
    }
    static var moveDown: String {
        String(localized: "Move down", bundle: .module, comment: "To-dos widget: context menu item and VoiceOver action")
    }
    static var delete: String {
        String(localized: "Delete", bundle: .module,
               comment: "To-dos widget: context menu item, VoiceOver action and Undo action name for one to-do")
    }
    static var deleteCompleted: String {
        String(localized: "Delete completed", bundle: .module,
               comment: "To-dos widget options: button that deletes every checked to-do (also the Undo action name)")
    }

    /// VoiceOver gets the widget's shortcuts as a hint (DESIGN.md §6.5).
    static var rowHint: String {
        String(localized: "Space checks it, Return edits it, Command-Up and Command-Down move it.", bundle: .module,
               comment: "To-dos widget: VoiceOver hint on a to-do (its keyboard shortcuts)")
    }

    // MARK: Options

    static var hideCompleted: String {
        String(localized: "Hide completed", bundle: .module,
               comment: "To-dos widget options: toggle that collapses checked to-dos after a moment")
    }

    // MARK: Errors

    static var loadFailed: String {
        String(localized: "Couldn’t load your to-dos", bundle: .module, comment: "To-dos widget: error state message")
    }
    static var saveFailed: String {
        String(localized: "Couldn’t save your to-dos", bundle: .module,
               comment: "To-dos widget: header warning button label and tooltip after a failed save")
    }
    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "To-dos widget: error state retry button")
    }

    // MARK: Command palette

    /// Extra search terms for "New to-do", localized as one space-separated line.
    static var newTodoKeywords: [String] {
        String(localized: "todo task add", bundle: .module,
               comment: "Command palette: search keywords for “New to-do”, separated by spaces (translate, keep the spaces)")
            .split(separator: " ").map(String.init)
    }

    // MARK: Samples (Settings and onboarding stages, previews)

    static var sampleTitles: [String] {
        [String(localized: "Water the plants", bundle: .module, comment: "To-dos widget: sample to-do on preview stages"),
         String(localized: "Reply to Sam", bundle: .module, comment: "To-dos widget: sample to-do on preview stages"),
         String(localized: "Book train tickets", bundle: .module, comment: "To-dos widget: sample to-do on preview stages"),
         String(localized: "Back up the laptop", bundle: .module, comment: "To-dos widget: sample to-do on preview stages")]
    }
}
