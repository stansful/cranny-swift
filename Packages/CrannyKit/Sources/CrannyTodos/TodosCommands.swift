// CrannyTodos/TodosCommands.swift — ⌘K (DESIGN.md §6.4): "New to-do", and the to-dos themselves when the query
// matches one (choosing it opens Cranny on that row). Offered only while the widget is on a page, because both
// need it on screen. In Demo mode with redaction no titles are listed. In-memory filtering only.
import CrannyCore
import Foundation

final class TodosCommands: PaletteCommandProvider {
    /// At most this many matching to-dos (the palette shows four rows).
    static let maximumMatches = 4

    private let model: TodosModel

    init(model: TodosModel) { self.model = model }

    func commands(matching query: String) -> [PaletteCommand] {
        guard let page = Self.page(showing: .todos, in: model.settings[CoreSettings.pages]) else { return [] }
        let query = query.trimmingCharacters(in: .whitespaces)
        var results: [PaletteCommand] = []

        let newTodo = PaletteCommand(id: "todos.new", title: TodosStrings.newTodo, kind: TodosStrings.title,
                                     symbol: "plus", keywords: TodosStrings.newTodoKeywords) { [model] in
            model.notch.open(page: page, focus: .todos, reason: .keyboard)
            model.beginNew(after: nil)
            model.notch.requestKeyboardFocus()
        }
        if query.isEmpty || Self.matches(query, newTodo.title) || newTodo.keywords.contains(where: { Self.matches(query, $0) }) {
            results.append(newTodo)
        }

        let redacts = model.environment.isDemoMode && model.settings[CoreSettings.demoRedactsCalendar]
        guard !query.isEmpty, !redacts else { return results }
        let found = model.visibleItems.filter { !$0.title.isBlank && Self.matches(query, $0.title) }
        let matches = (found.filter { !$0.isDone } + found.filter(\.isDone)).prefix(Self.maximumMatches)   // open first
        for todo in matches {
            results.append(PaletteCommand(id: CommandID("todos.item.\(todo.id.uuidString)"), title: todo.title,
                                          kind: TodosStrings.title,
                                          symbol: todo.isDone ? "checkmark.circle.fill" : "circle") { [model] in
                model.notch.open(page: page, focus: .todos, reason: .keyboard)
                model.requestSelection(.item(todo.id))
                model.notch.requestKeyboardFocus()
            })
        }
        return results
    }

    /// The first grid page that shows `widget`, nil if none does.
    static func page(showing widget: WidgetID, in pages: [NookPage]) -> PageID? {
        pages.first { $0.items.contains { $0.widget == widget } }?.id
    }

    /// Case-, diacritic- and width-insensitive "contains", in the user's locale.
    static func matches(_ query: String, _ text: String) -> Bool {
        text.localizedStandardContains(query)
    }
}
