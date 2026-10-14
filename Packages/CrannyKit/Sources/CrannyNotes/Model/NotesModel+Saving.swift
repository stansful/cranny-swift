// CrannyNotes/Model/NotesModel+Saving.swift — turning edits into change sets for `NotesStore`: autosave (at
// most 0.5 s after the first unsaved change), retry after a failure, and the synchronous flush on terminate.
//   • Typing writes the note's text file only. `index.json` (titles, modes, order, dates) is written when one of those
//     changes; the modification dates typing moves ride along then, and when the panel closes or the app quits.
//   • Saves run at utility priority: nobody waits for them (the terminate flush is synchronous).
//   • Saves run one after another (each waits for the previous), so change sets reach the disk in revision order:
//     a newer index never lands before the text file of a note it lists.
//   • A change set stays in `savesInFlight` until its save finished; `flush()` writes those again with everything
//     still pending, so quitting while a save waits for the store loses nothing (the store's ledger turns the late
//     write into a no-op).
//   • A failed save keeps the edits and retries after 5 s, 30 s and 2 min, then waits for the next edit, the next
//     time the Nook opens or the warning's retry button: no endless background I/O (§9.2).
import CrannyCore
import Foundation
import os

private let log = Log.logger(.notes)

extension NotesModel {
    /// Delays of the automatic retries after consecutive failures; after the last one, retries wait for the user.
    static let retryDelays: [Duration] = [.seconds(5), .seconds(30), .seconds(120)]

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
            change.index = currentIndex()
            indexDirty = false
            datesDirty = false                                                  // the index carries the current dates
        }
        dirtyTexts.removeAll()
        removedNotes.removeAll()
        return change
    }

    private func currentIndex() -> NotesIndex {
        NotesIndex(notes: entries.compactMap { documents[$0.id]?.entry })
    }

    /// Autosave: writes off the main actor, after the previous save. A failure puts the edits back and retries
    /// later. Returns the save (tests await it); nil when there was nothing to write.
    @discardableResult func saveNow() -> Task<Void, Never>? {
        guard let change = makeChangeSet() else { return nil }
        savesInFlight[change.revision] = change
        let store = store
        let previous = lastSave
        let save = Task(priority: .utility) { [weak self] in
            await previous?.value
            do {
                try await store.save(change)
                self?.saveFinished(change, error: nil)
            } catch {
                log.error("saving notes failed: \(error.localizedDescription, privacy: .public)")
                self?.saveFinished(change, error: error)
            }
        }
        lastSave = save
        return save
    }

    /// The terminate hook: writes what is pending — including change sets whose save has not run yet —
    /// synchronously (ARCHITECTURE.md §3.4, "fast and synchronous").
    func flush() {
        autosave.cancel()
        retryTask?.cancel()
        retryTask = nil
        guard let change = makeFinalChangeSet() else { return }
        do {
            try store.write(change)
            savesInFlight.removeAll()
        } catch {
            log.error("saving notes on quit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pending edits plus every change set still in flight, at a new revision, from the current texts, with the
    /// index if any date is newer than the one on disk.
    func makeFinalChangeSet() -> NotesChangeSet? {
        for change in savesInFlight.values {
            dirtyTexts.formUnion(change.texts.keys.filter { documents[$0] != nil })
            removedNotes.formUnion(change.removed)
            if change.index != nil { indexDirty = true }
        }
        if datesDirty { indexDirty = true }
        return makeChangeSet()
    }

    /// The panel closed: the dates typing moved are written with the index now (one write per session of typing),
    /// so `index.json` is never behind by more than the time the panel is open.
    func saveDatesSoon() {
        guard datesDirty else { return }
        indexDirty = true
        autosave.schedule()
    }

    /// The warning's retry button and the Nook opening after a failure: try again now, with a fresh backoff.
    func retrySave() {
        guard saveFailed else { return }
        retryTask?.cancel()
        retryTask = nil
        consecutiveSaveFailures = 0
        if saveNow() == nil { saveFailed = false }                              // nothing left to write
    }

    private func saveFinished(_ change: NotesChangeSet, error: (any Error)?) {
        savesInFlight[change.revision] = nil
        guard error != nil else {
            consecutiveSaveFailures = 0
            if saveFailed { saveFailed = false }
            return
        }
        dirtyTexts.formUnion(change.texts.keys.filter { documents[$0] != nil })
        removedNotes.formUnion(change.removed)
        if change.index != nil { indexDirty = true }
        saveFailed = true
        consecutiveSaveFailures += 1
        retryTask?.cancel()
        retryTask = nil
        guard consecutiveSaveFailures <= Self.retryDelays.count else {
            log.info("notes: automatic save retries exhausted; waiting for an edit or a retry")
            return
        }
        let delay = Self.retryDelays[consecutiveSaveFailures - 1]
        let sleep = retrySleep
        retryTask = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
