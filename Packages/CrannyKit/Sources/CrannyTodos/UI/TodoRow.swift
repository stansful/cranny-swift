// CrannyTodos/UI/TodoRow.swift — one 22-pt row: the circle + the title in `body` (DESIGN.md §7.6). Checked:
// struck through and tertiary until it collapses. Click the circle to check, the title to edit; the context
// menu and VoiceOver actions cover the rest. For VoiceOver the row is one toggle named by its text (§10.7).
// Every input is a value (no closures) and the menu reads no list state, so a keystroke in one row re-renders that
// row only: SwiftUI skips the rows whose inputs did not change.
import CrannyCore
import SwiftUI

struct TodoRow: View {
    @Environment(\.cranny) private var theme
    @Environment(\.undoManager) private var undoManager
    let todo: Todo
    let model: TodosModel
    let metrics: TodoMetrics
    let checkStyle: TodoCheckStyle
    /// Preview stages, layout editing, redaction: drawn, but never changes anything.
    let isReadOnly: Bool
    let redacts: Bool
    /// Keyboard selection inside a focused list: draws the focus ring.
    let showsFocusRing: Bool
    /// Whether Move up / Move down can move it (it is not the first / last visible row).
    let canMoveUp: Bool
    let canMoveDown: Bool

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
                // The toggle semantics sit on the title, not the row: wrapping the row would swap its subtree
                // when editing starts and re-create the editor mid-focus.
                title.modifier(TodoRowAccessibility(todo: todo, model: model, isActive: !isReadOnly, onDelete: delete))
            }
        }
        .frame(height: metrics.rowHeight)
        .background { focusRing }
        .contextMenu { if !isReadOnly { menu } }
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
            .modifier(TextPointer(isActive: !isReadOnly))
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
        Button(TodosStrings.moveUp) { model.move(todo.id, .up) }.disabled(!canMoveUp)
        Button(TodosStrings.moveDown) { model.move(todo.id, .down) }.disabled(!canMoveDown)
        Divider()
        Button(TodosStrings.delete, role: .destructive) { delete() }
    }

    /// Delete from the menu or VoiceOver, with Undo on the window's undo manager (as ⌘⌫ in the list).
    private func delete() {
        guard let removal = model.delete(todo.id) else { return }
        TodoUndo.registerRestore([removal], model: model, undoManager: undoManager, actionName: TodosStrings.delete)
    }
}

/// The I-beam over an editable title (macOS 15+; on 14 the arrow stays, the title still edits on click).
private struct TextPointer: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *), isActive {
            content.pointerStyle(.horizontalText)
        } else {
            content
        }
    }
}

/// VoiceOver: one toggle per row, named by its text, with Edit / Move up / Move down / Delete actions and the
/// shortcuts as a hint. While the row is being edited, the text field is exposed instead.
private struct TodoRowAccessibility: ViewModifier {
    let todo: Todo
    let model: TodosModel
    let isActive: Bool
    let onDelete: () -> Void

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
                .accessibilityAction(named: Text(verbatim: TodosStrings.delete)) { onDelete() }
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
                    showsFocusRing: todo.id == model.items.first?.id,
                    canMoveUp: todo.id != model.items.first?.id, canMoveDown: todo.id != model.items.last?.id)
        }
    }
    .frame(width: 160)
    .crannyCard(cells: 3)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
