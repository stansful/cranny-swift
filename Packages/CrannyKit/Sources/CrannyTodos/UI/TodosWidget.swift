// CrannyTodos/UI/TodosWidget.swift — the To-dos widget (DESIGN.md §7.6): 2–6 cells, 3 by default; at 2 cells
// the header has no count (§6.7). NotchUI draws the card, hover and VoiceOver container ("To-dos") around it.
import CrannyCore
import SwiftUI

final class TodosWidget: NookWidget {
    let model: TodosModel
    init(model: TodosModel) { self.model = model }

    let id: WidgetID = .todos
    var title: String { TodosStrings.title }
    let symbol = "checklist"
    var summary: String { TodosStrings.summary }
    let sizes = WidgetSizes(minimum: 2, preferred: 3, maximum: 6)

    func makeBody(context: WidgetContext) -> some View { TodosView(model: model, context: context) }
    func makeOptions() -> some View { TodosOptions(model: model) }
}

#Preview("Widget · 4 cells") {
    let widget = TodosWidget(model: .preview(TodosModel.sampleTodos(count: 3)))
    widget.makeBody(context: WidgetContext(cells: 4, contentSize: CGSize(width: 224, height: 96)))
        .crannyCard(cells: 4)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
