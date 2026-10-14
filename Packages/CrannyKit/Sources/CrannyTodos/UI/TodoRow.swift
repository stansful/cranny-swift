// CrannyTodos/UI/TodoRow.swift — one 22-pt row: the circle + the title in `body` (DESIGN.md §7.6). Checked:
// struck through and tertiary until it collapses. Click the circle to check, the title to edit; the context
// menu and VoiceOver actions cover the rest. For VoiceOver the row is one toggle named by its text (§10.7).
import CrannyCore
import SwiftUI

struct TodoRow: View {
    @Environment(\.cranny) private var theme
    let todo: Todo
    let model: TodosModel
    let metrics: TodoMetrics
    let checkStyle: TodoCheckStyle
    /// Preview stages, layout editing, redaction: drawn, but never changes anything.
    let isReadOnly: Bool
    let redacts: Bool
    /// Keyboard selection inside a focused list: draws the focus ring.
    let showsFocusRing: Bool
    let onDelete: (Todo.ID) -> Void

    private var isEditing: Bool { model.editingID == todo.id && !isReadOnly }

    var body: some View {
        HStack(spacing: Space.m) {
            TodoCheckbox(isDone: todo.isDone, style: checkStyle, metrics: metrics,
                         seed: TodoMote.seed(for: todo.id)) { model.toggle(todo.id) }
                .disabled(isReadOnly || todo.title.isBlank)
            if isEditing {
                TodoTitleField(text: todo.title, placeholder: TodosStrings.newTodo, style: .init(theme: theme),
                               onChange: { [model, id = todo.id] in model.setTitle($0, for: id) },
                               onCommand: { [model] in model.handle($0) },
                               onBegin: { [model] in model.editorDidBegin() },
                               onEnd: { [model, id = todo.id] in model.editorDidEnd(id) })
            } else {
                title
            }
        }
        .frame(height: metrics.rowHeight)
        .background { focusRing }
        .contextMenu { if !isReadOnly { menu } }
        .modifier(TodoRowAccessibility(todo: todo, model: model, isActive: !isEditing && !isReadOnly, onDelete: onDelete))
    }

    private var title: some View {
        let p = theme.palette
        return Text(todo.title)
            .crannyFont(.body)
            .strikethrough(todo.isDone, color: p.tertiaryLabel)
            .foregroundStyle(todo.isDone ? p.tertiaryLabel : p.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .redacted(reason: redacts ? .placeholder : [])
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !isReadOnly { model.beginEditing(todo.id) } }
            .help(redacts ? "" : todo.title)
            .animation(checkStyle.animation, value: todo.isDone)
    }

    /// The focus ring (2-pt accent, radius + 3, outset 3) around a rect inset so that the ring itself spans the
    /// row's full 22 pt and reaches 4 pt beyond its sides, with the `inner` radius of the card.
    private var focusRing: some View {
        Color.clear
            .crannyFocusRing(showsFocusRing, radius: theme.grid.innerRadius - Radius.focusRingOutset)
            .padding(.vertical, Radius.focusRingOutset)
            .padding(.horizontal, Radius.focusRingOutset - Space.xs)
    }

    @ViewBuilder private var menu: some View {
        Button(TodosStrings.edit) { model.beginEditing(todo.id) }
        Button(todo.isDone ? TodosStrings.markNotDone : TodosStrings.markDone) { model.toggle(todo.id) }
            .disabled(todo.title.isBlank)
        Divider()
        Button(TodosStrings.moveUp) { model.move(todo.id, .up) }.disabled(!model.canMove(todo.id, .up))
        Button(TodosStrings.moveDown) { model.move(todo.id, .down) }.disabled(!model.canMove(todo.id, .down))
        Divider()
        Button(TodosStrings.delete, role: .destructive) { onDelete(todo.id) }
    }
}

/// VoiceOver: one toggle per row, named by its text, with Edit / Move up / Move down / Delete actions.
/// While the row is being edited, the text field itself is exposed instead.
private struct TodoRowAccessibility: ViewModifier {
    let todo: Todo
    let model: TodosModel
    let isActive: Bool
    let onDelete: (Todo.ID) -> Void

    func body(content: Content) -> some View {
        if isActive {
            content
                .accessibilityRepresentation {
                    Toggle(isOn: Binding(get: { todo.isDone }, set: { _ in model.toggle(todo.id) })) {
                        Text(verbatim: todo.title)
                    }
                }
                .accessibilityHint(Text(verbatim: TodosStrings.rowHint))
                .accessibilityAction(named: Text(verbatim: TodosStrings.edit)) { model.beginEditing(todo.id) }
                .accessibilityAction(named: Text(verbatim: TodosStrings.moveUp)) { model.move(todo.id, .up) }
                .accessibilityAction(named: Text(verbatim: TodosStrings.moveDown)) { model.move(todo.id, .down) }
                .accessibilityAction(named: Text(verbatim: TodosStrings.delete)) { onDelete(todo.id) }
        } else {
            content
        }
    }
}

#Preview("Rows") {
    let model = TodosModel.preview()
    let metrics = TodoMetrics(textSize: .standard)
    VStack(spacing: 0) {
        ForEach(model.items) { todo in
            TodoRow(todo: todo, model: model, metrics: metrics, checkStyle: .draw, isReadOnly: false, redacts: false,
                    showsFocusRing: todo.id == model.items.first?.id, onDelete: { _ in })
        }
    }
    .frame(width: 160)
    .crannyCard(cells: 3)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
