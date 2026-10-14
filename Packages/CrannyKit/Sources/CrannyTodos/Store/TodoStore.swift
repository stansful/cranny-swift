// CrannyTodos/Store/TodoStore.swift — the list in memory plus its persistence: loaded once on launch,
// saved 0.5 s after the last edit (debounced, off the main actor) and flushed synchronously on quit.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.todos)

@MainActor @Observable final class TodoStore {
    enum Phase: Equatable {
        case loading, ready
        /// The file exists but could not be read, or is corrupt and could not be moved aside: show the error
        /// state and never save over it.
        case failed
    }

    private(set) var list = TodoList()
    private(set) var phase: Phase
    /// The last save failed; cleared by the next successful one.
    private(set) var saveFailed = false

    @ObservationIgnored private let storage: TodoStorage?
    @ObservationIgnored private let saveDebouncer: Debouncer
    /// Bumped by every edit; `savedRevision` is the newest one known to be on disk.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var savedRevision = 0

    /// `storage == nil`: in memory only (previews, tests), ready at once.
    init(storage: TodoStorage?, saveDelay: Duration = .milliseconds(500)) {
        self.storage = storage
        self.phase = storage == nil ? .ready : .loading
        self.saveDebouncer = Debouncer(delay: saveDelay)
    }

    /// A ready, in-memory store holding `items` (previews and tests).
    static func inMemory(_ items: [Todo]) -> TodoStore {
        let store = TodoStore(storage: nil)
        store.list = TodoList(items)
        return store
    }

    // MARK: Loading

    /// Reads the file off the main actor. To-dos created before it finished (type-to-capture right after
    /// launch) are kept after the loaded ones.
    func load() async {
        guard let storage else { phase = .ready; return }
        phase = .loading
        do {
            let outcome = try await storage.load()
            var loaded = TodoList()
            if case .loaded(let document) = outcome { loaded = TodoList(document.items) }
            loaded.removeBlank()
            let early = list.items.filter { loaded.index(of: $0.id) == nil }
            for todo in early { loaded.insert(todo, after: nil) }
            list = loaded
            phase = .ready
            log.info("loaded \(loaded.items.count, privacy: .public) to-dos")
            if !early.contains(where: { !$0.title.isBlank }) { savedRevision = revision } else { markDirty() }
        } catch {
            phase = .failed
            log.error("cannot read to-dos: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Editing

    /// The only way to change the list: applies `change` and schedules a save if anything changed.
    func update(_ change: (inout TodoList) -> Void) {
        var copy = list
        change(&copy)
        guard copy != list else { return }
        list = copy
        markDirty()
    }

    private func markDirty() {
        revision += 1
        saveDebouncer.schedule { [weak self] in await self?.save() }
    }

    // MARK: Saving

    /// What goes to disk: everything except blank drafts.
    var document: TodoDocument { TodoDocument(items: list.items.filter { !$0.title.isBlank }) }

    /// Writes the current revision off the main actor (no-op when nothing changed or the load failed).
    func save() async {
        guard phase == .ready, let storage, revision > savedRevision else { return }
        let target = revision
        do {
            try await storage.write(document, revision: target)
            savedRevision = max(savedRevision, target)
            saveFailed = false
        } catch {
            saveFailed = true
            log.error("cannot save to-dos: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `applicationWillTerminate`: writes synchronously if anything is unsaved (the one write on the main actor).
    func flush() {
        saveDebouncer.cancel()
        guard phase == .ready, let storage, revision > savedRevision else { return }
        do {
            try storage.writeNow(document, revision: revision)
            savedRevision = revision
        } catch {
            log.error("cannot save to-dos at quit: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The header's retry button after a failed save.
    func retrySave() {
        guard saveFailed else { return }
        revision += 1                                   // force a write even if nothing changed since
        Task { await save() }
    }
}
