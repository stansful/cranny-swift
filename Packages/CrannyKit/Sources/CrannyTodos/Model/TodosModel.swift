// CrannyTodos/Model/TodosModel.swift — the module's façade: the store, the editor (one title edited at a time,
// shared by every panel that shows the widget), the 1.2-s linger of checked items, and completion feedback.
// Views, ⌘K commands and type-to-capture all go through it; the edit flows are unit-tested here.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.todos)

@MainActor @Observable final class TodosModel {
    /// A request for the widget to select (and scroll to) a row. `serial` makes repeated requests observable.
    struct SelectionRequest: Equatable {
        let selection: TodoSelection
        let serial: Int
    }

    let store: TodoStore
    /// The to-do whose title is being edited, nil when none.
    private(set) var editingID: Todo.ID?
    /// Checked to-dos that stay visible, struck through, until they collapse (DESIGN.md §7.6).
    private(set) var lingering: Set<Todo.ID> = []
    private(set) var selectionRequest: SelectionRequest?

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let environment: any SystemEnvironment
    @ObservationIgnored let notch: any NotchControl
    @ObservationIgnored private let feedback: TodoFeedback
    @ObservationIgnored private let lingerDelay: Duration
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private(set) var lingerTasks: [Todo.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var notchObserver: UUID?
    @ObservationIgnored private var selectionSerial = 0

    init(store: TodoStore, settings: SettingsStore, environment: any SystemEnvironment, notch: any NotchControl,
         feedback: TodoFeedback, lingerDelay: Duration = TodoDelightTiming.linger,
         now: @escaping @MainActor () -> Date = { Date() }) {
        self.store = store
        self.settings = settings
        self.environment = environment
        self.notch = notch
        self.feedback = feedback
        self.lingerDelay = lingerDelay
        self.now = now
    }

    /// The app's model: `todos.json` under `services.paths`, live haptics and sounds. No I/O here.
    convenience init(services: CrannyServices) {
        self.init(store: TodoStore(storage: TodoStorage(url: TodosQA.storageURL ?? TodoStorage(paths: services.paths).url)),
                  settings: services.settings, environment: services.environment, notch: services.notch,
                  feedback: .live(haptics: services.haptics))
    }

    // MARK: Lifecycle

    /// `onLaunch`: reads the file and starts listening for the panel closing or changing page (both end editing).
    func start() async {
        if notchObserver == nil {
            notchObserver = notch.addEventObserver { [weak self] event in
                switch event {
                case .closed, .pageChanged: self?.endEditing()
                default: break
                }
            }
        }
        await store.load()
        TodosQA.apply(to: self)
    }

    /// The error state's "Try again".
    func reload() { Task { await store.load() } }

    /// The header's save error (click, ↩ / Space on it, VoiceOver): writes the list again.
    func retrySave() { store.retrySave() }

    /// `onTerminate`: ends editing and writes anything unsaved, synchronously.
    func flush() {
        endEditing()
        store.flush()
    }

    // MARK: Queries

    var hidesCompleted: Bool { settings[TodosSettings.hidesCompleted] }
    var items: [Todo] { store.list.items }
    var visibleItems: [Todo] { store.list.visible(hidesCompleted: hidesCompleted, lingering: lingering) }
    var remainingCount: Int { store.list.remainingCount }
    var completedCount: Int { store.list.completedCount }
    /// The header's "3 left" / "All done" / nothing.
    var headerCount: TodoHeaderCount { store.list.headerCount }
    func item(_ id: Todo.ID) -> Todo? { store.list.item(id) }
    private var visibleIDs: [Todo.ID] { visibleItems.map(\.id) }

    /// How the check appears right now (personality and Reduce Motion come from the theme).
    func checkStyle(personality: MotionPersonality, reduceMotion: Bool) -> TodoCheckStyle {
        .resolve(personality: personality, reduceMotion: reduceMotion,
                 isFullScreenInFront: environment.isFullScreenInFront,
                 areActivitiesPaused: environment.areLiveActivitiesPaused)
    }

    // MARK: Checking

    /// Click on the circle, Space, VoiceOver toggle. Blank drafts cannot be checked.
    func toggle(_ id: Todo.ID) {
        guard let todo = item(id), !todo.title.isBlank else { return }
        if editingID == id { endEditing() }
        let done = !todo.isDone
        store.update { $0.setDone(done, for: id, at: now()) }
        if done {
            feedback.haptic()
            if TodoFeedback.playsSound(uiSounds: settings[CoreSettings.uiSounds], isDemoMode: environment.isDemoMode) {
                feedback.sound(TodoFeedback.completionSound)
            }
            if hidesCompleted { linger(id) }
        } else {
            endLinger(id)
        }
    }

    /// Keeps a checked item visible for `lingerDelay`, then lets it collapse. One sleep, no timer.
    private func linger(_ id: Todo.ID) {
        lingerTasks[id]?.cancel()
        lingering.insert(id)
        lingerTasks[id] = Task { [weak self, lingerDelay] in
            try? await Task.sleep(for: lingerDelay)
            guard !Task.isCancelled else { return }
            self?.endLinger(id)
        }
    }

    private func endLinger(_ id: Todo.ID) {
        lingerTasks.removeValue(forKey: id)?.cancel()
        lingering.remove(id)
    }

    // MARK: Editing

    /// Starts a new, empty to-do after `anchor` (nil = at the end) and edits it. Never stacks two drafts.
    @discardableResult
    func beginNew(after anchor: Todo.ID?) -> Todo.ID {
        if let editingID, let todo = item(editingID), todo.title.isBlank, anchor == nil || anchor == editingID {
            return editingID
        }
        endEditing()
        let todo = Todo(title: "", created: now())
        let target = anchor.flatMap { item($0) } != nil ? anchor : nil
        store.update { $0.insert(todo, after: target) }
        editingID = todo.id
        return todo.id
    }

    /// Click on a title, ↩ on a selected row, the VoiceOver "Edit" action.
    func beginEditing(_ id: Todo.ID) {
        guard editingID != id, item(id) != nil else { return }
        endEditing()
        editingID = id
    }

    /// Every keystroke in the editor (saved 0.5 s after the last one).
    func setTitle(_ title: String, for id: Todo.ID) {
        store.update { $0.setTitle(title, for: id) }
    }

    /// ↩ in the editor: a blank row just stops editing; otherwise the next to-do starts below this one.
    func commitEditing() {
        guard let id = editingID, let todo = item(id) else { return }
        if todo.title.isBlank { endEditing() } else { beginNew(after: id) }
    }

    /// Esc, focus leaving the editor, the Nook closing: trims the title, drops the row if it is blank.
    func endEditing() {
        guard let id = editingID else { return }
        editingID = nil
        guard let todo = item(id) else { return }
        let title = TodoList.trimmed(todo.title)
        store.update { list in
            if title.isEmpty { list.remove(id) } else { list.setTitle(title, for: id) }
        }
    }

    /// The editor lost focus (click elsewhere, Tab): ends editing if it was still this row's.
    func editorDidEnd(_ id: Todo.ID) {
        if editingID == id { endEditing() }
    }

    /// The editor became first responder: the panel must be key for typing (non-activating panel).
    func editorDidBegin() {
        notch.requestKeyboardFocus()
    }

    /// Keys from the title editor. Returns false to let the field editor handle the key itself.
    func handle(_ command: TodoEditorCommand) -> Bool {
        guard let id = editingID else { return false }
        switch command {
        case .commit:
            commitEditing()
            return true
        case .cancel:
            let above = TodoList.neighbor(of: id, .up, in: visibleIDs)
            endEditing()
            requestSelection(item(id) != nil ? .item(id) : above.map(TodoSelection.item) ?? .newRow)
            return true
        case .deleteBackward:
            return deleteIfEmpty(id)
        case .previous, .next:
            guard let target = TodoList.neighbor(of: id, command == .previous ? .up : .down, in: visibleIDs) else { return false }
            beginEditing(target)
            return true
        case .moveUp, .moveDown:
            move(id, command == .moveUp ? .up : .down)
            return true
        }
    }

    /// ⌫ on an empty row deletes it and continues editing the row above (DESIGN.md §7.6).
    private func deleteIfEmpty(_ id: Todo.ID) -> Bool {
        guard let todo = item(id), todo.title.isEmpty else { return false }
        let previous = TodoList.neighbor(of: id, .up, in: visibleIDs)
        editingID = nil
        store.update { $0.remove(id) }
        if let previous { editingID = previous } else { requestSelection(visibleIDs.first.map(TodoSelection.item) ?? .newRow) }
        return true
    }

    // MARK: Ordering and deleting

    /// ⌘↑ / ⌘↓ and the Move up / Move down menu items and VoiceOver actions.
    @discardableResult
    func move(_ id: Todo.ID, _ direction: TodoMoveDirection) -> Bool {
        let visible = Set(visibleIDs)
        var moved = false
        store.update { moved = $0.move(id, direction, visible: visible) }
        return moved
    }

    func canMove(_ id: Todo.ID, _ direction: TodoMoveDirection) -> Bool {
        TodoList.neighbor(of: id, direction, in: visibleIDs) != nil
    }

    /// Delete from the context menu, ⌘⌫ or VoiceOver. Returns what Undo needs.
    @discardableResult
    func delete(_ id: Todo.ID) -> TodoRemoval? {
        if editingID == id { editingID = nil }
        endLinger(id)
        var removal: TodoRemoval?
        store.update { removal = $0.remove(id) }
        return removal
    }

    /// "Delete completed" (widget options). Returns what Undo needs.
    @discardableResult
    func deleteCompleted() -> [TodoRemoval] {
        var removals: [TodoRemoval] = []
        store.update { removals = $0.removeCompleted() }
        for removal in removals { endLinger(removal.todo.id) }
        log.info("deleted \(removals.count, privacy: .public) completed to-dos")
        return removals
    }

    /// Undo of a delete.
    func restore(_ removals: [TodoRemoval]) {
        store.update { $0.restore(removals) }
    }

    // MARK: Selection requests (⌘K results, Esc from the editor)

    func requestSelection(_ selection: TodoSelection) {
        selectionSerial += 1
        selectionRequest = SelectionRequest(selection: selection, serial: selectionSerial)
    }

    /// The widget took the request (only one open panel shows it).
    func clearSelectionRequest() { selectionRequest = nil }

    // MARK: Type-to-capture

    /// The first keys typed in a Nook opened by the keyboard (`CaptureTarget` "todos"): a new to-do at the end
    /// holding them, with its editor focused. Returns the widget the shell should focus.
    func capture(_ text: String) -> WidgetID {
        let id = beginNew(after: nil)
        setTitle(text, for: id)
        return .todos
    }
}
