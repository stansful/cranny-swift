// CrannyTodos/UI/TodoListView.swift — the header, the rows, the trailing "New to-do" row and the keyboard
// (DESIGN.md §7.6, §16). The widget is one focus stop (Tab reaches it like any widget); arrows move a selection
// drawn as the accent focus ring, up to the header's save error while there is one; the title editor takes over
// while a row is edited. The rows scroll when the card is full, with a 12-pt fade at the bottom; they never
// stagger (§4.5). Checked rows collapse with `listReorder`.
import AppKit
import CrannyCore
import SwiftUI

struct TodoListView<Header: View>: View {
    @Environment(\.cranny) private var theme
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isListFocused: Bool
    @State private var selection: TodoSelection?
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    let model: TodosModel
    let items: [Todo]
    let metrics: TodoMetrics
    let checkStyle: TodoCheckStyle
    let isReadOnly: Bool
    let redacts: Bool
    /// The shell moved keyboard focus to this widget (`WidgetContext.isFocused`).
    let isFocusedWidget: Bool
    /// The header shows the save error, which the selection can reach (↑ from the first row).
    let hasSaveError: Bool
    /// The header above the rows; its argument is true while the save error is selected (draw the ring).
    @ViewBuilder let header: (_ showsSaveErrorRing: Bool) -> Header

    private var ids: [Todo.ID] { items.map(\.id) }
    /// A new, still blank to-do is being typed: it stands in for the "New to-do" row, which would repeat it.
    private var isDrafting: Bool { model.editingID.flatMap(model.item)?.title.isBlank == true }
    /// Room for the focus ring, which reaches 4 pt beyond a row's sides, inside the scroll view's clip.
    private var ringRoom: CGFloat { Space.s }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            header(isListFocused && selection == .saveError)
            rows
        }
        .allowsHitTesting(!isReadOnly)
        .focusable(!isReadOnly, interactions: .edit)
        .focused($isListFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press) }
        .onChange(of: isListFocused) { _, focused in
            // Focus arriving from the keyboard (Tab, the shell) selects the first row; a click does not.
            if focused, selection == nil, NSApp.currentEvent?.type == .keyDown {
                selection = firstRow
            }
        }
        .onChange(of: ids) { old, new in
            if case .item(let id)? = selection, !new.contains(id) {
                selection = TodoKeyMap.selection(replacing: id, oldVisible: old, newVisible: new)
            }
        }
        .onChange(of: hasSaveError) { _, has in
            if !has, selection == .saveError { selection = firstRow }        // saved: back to the rows
        }
        .onChange(of: model.selectionRequest) { _, _ in applySelectionRequest() }
        .onChange(of: isFocusedWidget) { _, focused in if focused { focusList() } }
        .onChange(of: isReadOnly) { _, readOnly in if readOnly { model.endEditing() } }   // ⌘E, Demo redaction
        .onAppear {
            applySelectionRequest()
            if isFocusedWidget { focusList() }
        }
        .animation(theme.animation(.listReorder), value: ids)
    }

    private var firstRow: TodoSelection { ids.first.map(TodoSelection.item) ?? .newRow }

    private var rows: some View {
        let overflows = contentHeight > viewportHeight + 0.5
        // The rows' Move up / Move down state, from the shown rows once (live, `items` are the visible ones, so this is
        // `TodosModel.canMove`); values, not closures, so unchanged rows are not rendered again.
        let first = items.first?.id, last = items.last?.id
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { todo in
                        TodoRow(todo: todo, model: model, metrics: metrics, checkStyle: checkStyle,
                                isReadOnly: isReadOnly, redacts: redacts,
                                showsFocusRing: isListFocused && selection == .item(todo.id),
                                canMoveUp: todo.id != first, canMoveDown: todo.id != last)
                            .id(TodoSelection.item(todo.id))
                            .transition(.opacity)
                    }
                    if !isReadOnly && !isDrafting {
                        NewTodoRow(metrics: metrics, showsFocusRing: isListFocused && selection == .newRow) {
                            model.beginNew(after: nil)
                        }
                        .id(TodoSelection.newRow)
                    }
                    if overflows {
                        Color.clear.frame(height: metrics.fade).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, ringRoom)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewportHeight = $0 }
            .mask { fadeMask(overflows) }
            .padding(.horizontal, -ringRoom)                 // after the mask, so the ring is not clipped either
            .onChange(of: model.editingID) { _, id in
                if let id { scroll(proxy, to: .item(id)) }
            }
            .onChange(of: selection) { _, target in
                if let target, target != .saveError { scroll(proxy, to: target) }
            }
        }
    }

    // MARK: Keyboard

    /// What the ⌫ key actually sends on the Mac (DEL, U+007F); SwiftUI's `.delete` is backspace (U+0008).
    private static var deleteKey: KeyEquivalent { KeyEquivalent("\u{7F}") }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !isReadOnly, model.editingID == nil else { return .ignored }
        let others: EventModifiers = [.option, .control, .shift]
        guard press.modifiers.isDisjoint(with: others) else { return .ignored }
        let key: TodoListKey
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .space: key = .space
        case .return: key = .returnKey
        case .delete, Self.deleteKey: key = .deleteBackward
        default: return .ignored
        }
        guard let command = TodoKeyMap.command(for: key, command: press.modifiers.contains(.command),
                                               selection: selection, visible: ids,
                                               hasSaveError: hasSaveError) else { return .ignored }
        perform(command)
        return .handled
    }

    private func perform(_ command: TodoListCommand) {
        switch command {
        case .select(let target): selection = target
        case .toggle(let id): model.toggle(id)
        case .edit(let id): model.beginEditing(id)
        case .newItem: model.beginNew(after: nil)
        case .move(let id, let direction): model.move(id, direction)
        case .delete(let id): delete(id)
        case .retrySave: model.retrySave()
        }
    }

    private func delete(_ id: Todo.ID) {
        guard let removal = model.delete(id) else { return }
        TodoUndo.registerRestore([removal], model: model, undoManager: undoManager, actionName: TodosStrings.delete)
    }

    // MARK: Focus and selection

    private func focusList() {
        guard !isReadOnly, model.editingID == nil else { return }
        isListFocused = true
        if selection == nil { selection = firstRow }
    }

    /// ⌘K results and Esc from the editor ask for a row; the first list that sees the request takes it.
    private func applySelectionRequest() {
        guard !isReadOnly, let request = model.selectionRequest else { return }
        model.clearSelectionRequest()
        selection = request.selection
        isListFocused = true
    }

    private func scroll(_ proxy: ScrollViewProxy, to target: TodoSelection) {
        withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(target) }
    }

    // MARK: Drawing

    /// A 12-pt fade at the bottom while the list scrolls, so a cut-off row reads as "more below".
    @ViewBuilder private func fadeMask(_ overflows: Bool) -> some View {
        if overflows {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: metrics.fade)
            }
        } else {
            Rectangle()
        }
    }
}

#Preview("List · scrolling") {
    let model = TodosModel.preview(TodosModel.sampleTodos(count: 6, completed: [1]))
    let metrics = TodoMetrics(textSize: .standard)
    TodoListView(model: model, items: model.visibleItems, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                 redacts: false, isFocusedWidget: false, hasSaveError: false) { _ in
        TodosHeader(count: model.headerCount, showsCount: true, saveFailed: false, metrics: metrics) {}
    }
        .crannyCard(cells: 3)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
