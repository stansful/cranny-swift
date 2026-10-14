// CrannyTodos/UI/TodosOptions.swift — the widget's options popover (Settings ▸ Layout & Widgets and the card's ⋯
// menu, DESIGN.md §11.1): "Hide completed", and "Delete completed" (undoable) so hidden checked to-dos never
// pile up out of reach. System controls: the popover lives in ordinary windows as well as in the notch.
import CrannyCore
import SwiftUI

struct TodosOptions: View {
    @Environment(\.undoManager) private var undoManager
    let model: TodosModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle(isOn: model.settings.binding(TodosSettings.hidesCompleted)) {
                Text(TodosStrings.hideCompleted)
            }
            Button(role: .destructive) {
                let removals = model.deleteCompleted()
                TodoUndo.registerRestore(removals, model: model, undoManager: undoManager,
                                         actionName: TodosStrings.deleteCompleted)
            } label: {
                Text(TodosStrings.deleteCompleted)
            }
            .disabled(model.completedCount == 0)
        }
        .fixedSize()
    }
}

#Preview("Options") {
    TodosOptions(model: .preview(TodosModel.sampleTodos(count: 3, completed: [0])))
        .padding(Space.xl)
}
