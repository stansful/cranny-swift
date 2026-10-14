// CrannyNotes/Model/NotesModel+Saving.swift — turning edits into change sets for `NotesStore`: autosave (at
// most 0.5 s after the first unsaved change), retry after a failure, and the synchronous flush on terminate.
import CrannyCore
import Foundation
import os

private let log = Log.logger(.notes)

extension NotesModel {
    /// Seconds before a failed save is tried again (the text stays in memory meanwhile).
    static let retryDelay: Duration = .seconds(5)

    /// The pending edits as one change set (nil when there is nothing to write). The index is included only once
    /// the notes are loaded, so a save can never replace the list on disk with a partial one.
    func makeChangeSet() -> NotesChangeSet? {
        let writesIndex = indexDirty && phase == .loaded
        guard !dirtyTexts.isEmpty || !removedNotes.isEmpty || writesIndex else { return nil }
        revision += 1
        var change = NotesChangeSet(revision: revision)
        for id in dirtyTexts { if let note = documents[id] { change.texts[id] = note.text } }
        change.removed = removedNotes
        if writesIndex {
            change.index = NotesIndex(notes: entries.compactMap { documents[$0.id]?.entry })
            indexDirty = false
        }
        dirtyTexts.removeAll()
        removedNotes.removeAll()
        return change
    }

    /// Autosave: writes off the main actor. A failure puts the edits back and retries later.
    /// Returns the save (tests await it); nil when there was nothing to write.
    @discardableResult func saveNow() -> Task<Void, Never>? {
        guard let change = makeChangeSet() else { return nil }
        let store = store
        return Task { [weak self] in
            do {
                try await store.save(change)
                self?.saveSucceeded()
            } catch {
                log.error("saving notes failed: \(error.localizedDescription, privacy: .public)")
                self?.handleSaveFailure(change)
            }
        }
    }

    /// The terminate hook: writes what is pending synchronously (ARCHITECTURE.md §3.4, "fast and synchronous").
    func flush() {
        autosave.cancel()
        retryTask?.cancel()
        guard let change = makeChangeSet() else { return }
        do {
            try store.write(change)
        } catch {
            log.error("saving notes on quit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveSucceeded() {
        if saveFailed { saveFailed = false }
    }

    private func handleSaveFailure(_ change: NotesChangeSet) {
        dirtyTexts.formUnion(change.texts.keys.filter { documents[$0] != nil })
        removedNotes.formUnion(change.removed)
        if change.index != nil { indexDirty = true }
        saveFailed = true
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
