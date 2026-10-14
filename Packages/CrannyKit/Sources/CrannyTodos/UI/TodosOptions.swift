// CrannyTodos/UI/TodosOptions.swift — the widget's options popover (Settings ▸ Layout & Widgets and the card's ⋯
// menu, DESIGN.md §11.1): "Hide completed", and "Delete completed" (undoable) so hidden checked to-dos never
// pile up out of reach. System controls: the popover lives in ordinary windows as well as in the notch. The
// Undo goes to the window under the popover (the panel or Settings), where ⌘Z is pressed after it closes.
import CrannyCore
import SwiftUI

struct TodosOptions: View {
    @Environment(\.undoManager) private var undoManager
    @State private var anchor = TodoWindowAnchor()
    let model: TodosModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle(isOn: model.settings.binding(TodosSettings.hidesCompleted)) {
                Text(TodosStrings.hideCompleted)
            }
            Button(role: .destructive) {
                // Undo on the window below, not on the popover's own undo manager, which goes away with it.
                TodoUndo.deleteCompleted(model, hostedIn: anchor.window, fallback: undoManager)
            } label: {
                Text(TodosStrings.deleteCompleted)
            }
            .disabled(model.completedCount == 0)
        }
        .fixedSize()
        .background(TodoWindowAnchorView(anchor: anchor))
    }
}

#Preview("Options") {
    TodosOptions(model: .preview(TodosModel.sampleTodos(count: 3, completed: [0])))
        .padding(Space.xl)
}
