import CrannyCore
import Foundation
import Testing
@testable import CrannyTodos

/// ⌘K: "New to-do" and searching to-dos (DESIGN.md §6.4).
@MainActor
struct TodosCommandsTests {
    let services: CrannyServices
    let environment = PreviewSystemEnvironment()

    init() { services = .preview(environment: environment) }

    private func model(_ titles: [String]) -> TodosModel {
        TodosModel.preview(titles.map { Todo(title: $0) }, services: services)
    }
    private var notchCalls: [String] { (services.notch as? PreviewNotchControl)?.calls ?? [] }
    private func placeWidget(on page: PageID = .nook) {
        services.settings[CoreSettings.pages] = [NookPage(id: page, symbol: "square.grid.2x2.fill",
                                                          items: [.init(.notes, cells: 4), .init(.todos, cells: 3)])]
    }

    @Test func nothingIsOfferedWhileTheWidgetIsOnNoPage() {
        let commands = TodosCommands(model: model(["milk"]))
        #expect(commands.commands(matching: "").isEmpty)        // default layout (Listener) has no To-dos
        #expect(commands.commands(matching: "milk").isEmpty)
    }

    @Test func newToDoOpensTheWidgetAndStartsEditing() throws {
        placeWidget(on: "page.focus")
        let model = model(["a"])
        let commands = TodosCommands(model: model).commands(matching: "")
        let newTodo = try #require(commands.first)
        #expect(commands.count == 1)
        #expect(newTodo.id == "todos.new")
        #expect(newTodo.title == TodosStrings.newTodo)
        #expect(newTodo.kind == TodosStrings.title)
        newTodo.perform()
        #expect(notchCalls == ["open(page.focus,todos.list,keyboard)", "key"])
        #expect(model.editingID != nil)
        #expect(model.items.count == 2)
    }

    @Test func newToDoMatchesItsTitleAndKeywords() {
        placeWidget()
        let commands = TodosCommands(model: model([]))
        #expect(commands.commands(matching: "new").map(\.id) == ["todos.new"])
        #expect(commands.commands(matching: "task").map(\.id) == ["todos.new"])
        #expect(commands.commands(matching: "zebra").isEmpty)
    }

    @Test func matchingToDosAreListedOpenFirstAndRevealTheRow() throws {
        placeWidget()
        services.settings[TodosSettings.hidesCompleted] = false
        let model = model(["Buy milk", "Call mum", "Milk the cow", "Oat milk"])
        model.toggle(model.items[0].id)
        let results = TodosCommands(model: model).commands(matching: "MILK")
        #expect(results.map(\.title) == ["Milk the cow", "Oat milk", "Buy milk"])
        #expect(results.map(\.symbol) == ["circle", "circle", "checkmark.circle.fill"])
        let first = try #require(results.first)
        first.perform()
        #expect(model.selectionRequest?.selection == .item(model.items[2].id))
        #expect(notchCalls == ["open(nook,todos.list,keyboard)", "key"])
    }

    @Test func atMostFourMatches() {
        placeWidget()
        let model = model((1...9).map { "item \($0)" })
        #expect(TodosCommands(model: model).commands(matching: "item").count == TodosCommands.maximumMatches)
    }

    @Test func demoRedactionHidesTitles() {
        placeWidget()
        environment.isDemoMode = true
        let model = model(["secret plan"])
        #expect(TodosCommands(model: model).commands(matching: "secret").isEmpty)
        services.settings[CoreSettings.demoRedactsCalendar] = false
        #expect(TodosCommands(model: model).commands(matching: "secret").map(\.title) == ["secret plan"])
    }

    @Test func pageLookupFindsTheFirstPageWithTheWidget() {
        let pages = [NookPage(id: .nook, symbol: "a", items: [.init(.media, cells: 5)]),
                     NookPage(id: "page.2", symbol: "b", items: [.init(.todos, cells: 2)]),
                     NookPage(id: "page.3", symbol: "c", items: [.init(.todos, cells: 3)])]
        #expect(TodosCommands.page(showing: .todos, in: pages) == "page.2")
        #expect(TodosCommands.page(showing: .timer, in: pages) == nil)
    }

    @Test func matchingIgnoresCaseAndDiacritics() {
        #expect(TodosCommands.matches("cafe", "Café run"))
        #expect(TodosCommands.matches("ЗАДАЧ", "задача"))
        #expect(!TodosCommands.matches("tea", "coffee"))
    }
}
