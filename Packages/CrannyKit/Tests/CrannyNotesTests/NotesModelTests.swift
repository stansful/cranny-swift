// NotesModel with `CrannyServices.preview()` (temporary paths, in-memory settings, recording notch double).
import CrannyCore
import Foundation
import os
import Testing
@testable import CrannyNotes

@Suite("Notes model") final class NotesModelTests {
    private let services: CrannyServices
    private nonisolated let temporaryFolder: URL
    private var notch: PreviewNotchControl { services.notch as! PreviewNotchControl }   // the preview double

    init() {
        services = CrannyServices.preview()
        temporaryFolder = services.paths.root.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: temporaryFolder) }

    private func makeModel() -> NotesModel {
        NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
    }

    private func loadedModel() async -> NotesModel {
        let model = makeModel()
        await model.load()
        return model
    }

    // MARK: Creating, naming, selecting

    @Test func newNotesGetFreeUntitledNamesAtTheTop() async {
        let model = await loadedModel()
        let first = model.newNote()
        let second = model.newNote()
        #expect(model.entries.map(\.id) == [second, first])
        #expect(model.entry(first)?.title == NotesStrings.untitled)
        #expect(model.entry(second)?.title == NotesStrings.untitled(2))
        #expect(model.selectedID == second)
        #expect(model.focusRequested)
        #expect(model.emptyNotes.contains(second))
    }

    @Test func newNotesUseTheDefaultMode() async {
        services.settings[NotesSettings.defaultMode] = .code
        let model = await loadedModel()
        let id = model.newNote()
        #expect(model.entry(id)?.mode == .code)
    }

    @Test func nextAndPreviousWrapAroundAndAreRemembered() async {
        let model = await loadedModel()
        let a = model.newNote(), b = model.newNote(), c = model.newNote()        // list: c b a
        #expect(model.selectedID == c)
        model.selectNext()
        #expect(model.selectedID == b)
        model.selectNext(); model.selectNext()
        #expect(model.selectedID == c)                                          // wrapped
        model.selectNext(false)
        #expect(model.selectedID == a)
        #expect(services.settings[NotesSettings.lastNoteID] == a.uuidString)
    }

    @Test func returnAndEscEndARenameInTheNoteButAClickElsewhereDoesNot() async {
        let model = await loadedModel()
        let id = model.newNote(focus: false)
        model.beginRename()
        model.commitRename("Plan", returnsFocus: true)                          // Return
        #expect(model.entry(id)?.title == "Plan")
        #expect(model.focusRequested)
        model.consumeFocusRequest()
        model.beginRename()
        model.cancelRename()                                                    // Esc
        #expect(model.renamingID == nil)
        #expect(model.entry(id)?.title == "Plan")
        #expect(model.focusRequested)
        model.consumeFocusRequest()
        model.beginRename()
        model.commitRename("Plan B")                                            // the field lost focus
        #expect(model.entry(id)?.title == "Plan B")
        #expect(!model.focusRequested)                                          // the keyboard stays where it went
    }

    @Test func renameTrimsAndRefusesEmptyTitles() async {
        let model = await loadedModel()
        let id = model.newNote()
        model.beginRename()
        #expect(model.renamingID == id)
        #expect(notch.calls.contains("key"))                                    // typing the title needs a key panel
        model.commitRename("  build.swift \n")
        #expect(model.entry(id)?.title == "build.swift")
        #expect(model.renamingID == nil)
        model.beginRename()
        model.commitRename("   ")
        #expect(model.entry(id)?.title == "build.swift")
        #expect(NoteTitles.sanitized(String(repeating: "x", count: 500))?.count == NoteTitles.maximumLength)
    }

    @Test func modeAndLanguage() async {
        let model = await loadedModel()
        let id = model.newNote(text: "#!/bin/zsh\necho hi")
        model.toggleCodeMode()
        #expect(model.entry(id)?.mode == .code)
        #expect(model.effectiveLanguage(of: id) == .shell)
        model.setLanguage(.python, for: id)
        #expect(model.effectiveLanguage(of: id) == .python)
        #expect(model.entry(id)?.detectedLanguage == .shell)                    // the menu still shows "Automatic (Shell)"
        model.toggleCodeMode()
        #expect(model.entry(id)?.mode == .plain)
        #expect(model.entry(id)?.detectedLanguage == nil)
    }

    /// Typing never runs "Automatic": the entry keeps its language until the coalesced detection runs, and changes
    /// (re-rendering the header and restyling the editor once) only when the result does.
    @Test func automaticLanguageIsDetectedOffTheKeystroke() async {
        services.settings[NotesSettings.defaultMode] = .code
        let model = await loadedModel()
        let id = model.newNote()
        #expect(model.entry(id)?.detectedLanguage == nil)
        model.setText("import SwiftUI\nstruct Card: View {", for: id)
        #expect(model.entry(id)?.detectedLanguage == nil)                       // not on the keystroke
        #expect(model.languageDetection.isPending)
        model.languageDetection.fireNow()
        #expect(model.entry(id)?.detectedLanguage == .swift)
        let before = model.entries
        model.setText("import SwiftUI\nstruct Card: View { }", for: id)
        model.detectLanguages()
        #expect(model.entries == before)                                        // same result: no change at all
        model.setText("plain words", for: id)
        model.detectLanguages()
        #expect(model.entry(id)?.detectedLanguage == nil)
        model.languageDetection.cancel()
    }

    @Test func plainNotesAreNotDetected() async {
        let model = await loadedModel()
        let id = model.newNote()
        model.setText("import SwiftUI", for: id)
        #expect(!model.languageDetection.isPending)
        #expect(model.entry(id)?.detectedLanguage == nil)
    }

    /// Polls `condition` for up to 3 s (saves run off the main actor).
    private func waitUntil(_ condition: () throws -> Bool) async throws {
        for _ in 0..<150 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition not met within 3 s")
    }

    // MARK: Deleting

    @Test func deleteAsksThenSelectsTheNeighbour() async throws {
        let model = await loadedModel()
        let a = model.newNote(text: "a"), b = model.newNote(text: "b"), c = model.newNote(text: "c")   // c b a
        await model.saveNow()?.value
        model.select(b)
        model.requestDelete()
        #expect(model.pendingDeletion == b)
        #expect(model.entries.count == 3)                                       // nothing happens before confirming
        model.cancelDelete()
        #expect(model.pendingDeletion == nil)
        model.requestDelete()
        model.confirmDelete()
        #expect(model.entries.map(\.id) == [c, a])
        #expect(model.selectedID == a)                                          // the next one down
        let store = NotesStore(paths: services.paths)
        try await waitUntil { try store.loadNow().notes.count == 2 }            // the delete is saved at once
        let reloaded = try store.loadNow()
        #expect(reloaded.notes.map(\.id) == [c, a])
        #expect(reloaded.recovered == 0)
    }

    @Test func theConfirmationTakesTheKeyboardAndGivesItBackToANote() async {
        let model = await loadedModel()
        _ = model.newNote(text: "a", focus: false)
        let b = model.newNote(text: "b", focus: false)
        let before = notch.calls.count
        model.requestDelete()
        #expect(notch.calls.dropFirst(before) == ["key"])                       // Return and Esc reach the buttons
        model.cancelDelete()                                                    // Cancel / Esc
        #expect(model.pendingDeletion == nil && model.focusRequested)
        model.consumeFocusRequest()
        model.requestDelete()
        model.confirmDelete()                                                   // Delete / Return
        #expect(model.entry(b) == nil)
        #expect(model.focusRequested)                                           // typing goes on in the neighbour
        model.consumeFocusRequest()
        model.requestDelete()
        model.panelClosed()                                                     // closing is not "Cancel"
        #expect(model.pendingDeletion == nil && !model.focusRequested)
    }

    @Test func deletingTheLastNoteLeavesTheEmptyState() async {
        let model = await loadedModel()
        _ = model.newNote()
        model.requestDelete()
        model.confirmDelete()
        #expect(model.entries.isEmpty)
        #expect(model.selectedID == nil)
    }

    // MARK: Persistence

    @Test func textSurvivesARelaunch() async throws {
        let model = await loadedModel()
        let id = model.newNote()
        model.setText("first line\nsecond", for: id)
        #expect(!model.emptyNotes.contains(id))
        await model.saveNow()?.value
        let relaunched = await loadedModel()                                   // what a kill -9 + relaunch reads
        #expect(relaunched.text(of: id) == "first line\nsecond")
        #expect(relaunched.selectedID == id)                                    // lastNoteID
    }

    @Test func flushOnTerminateIsSynchronous() async throws {
        let model = await loadedModel()
        let id = model.newNote()
        model.setText("typed just before quitting", for: id)
        model.flush()                                                           // no await: the app exits next
        let reloaded = try NotesStore(paths: services.paths).loadNow()
        #expect(reloaded.notes.first { $0.id == id }?.text == "typed just before quitting")
        #expect(model.makeChangeSet() == nil)                                   // nothing left pending
    }

    /// A save handed to its task but not yet written when the app quits: the flush writes it (review of WP5).
    @Test func flushWritesSavesThatAreStillInFlight() async throws {
        let model = await loadedModel()
        let id = model.newNote()
        model.setText("typed, autosave started", for: id)
        let inFlight = model.saveNow()                                          // queued, has not run yet
        model.flush()                                                           // quit before it runs
        let afterQuit = try NotesStore(paths: services.paths).loadNow()
        #expect(afterQuit.notes.first { $0.id == id }?.text == "typed, autosave started")
        #expect(afterQuit.notes.contains { $0.id == id })                       // listed in the index too
        await inFlight?.value                                                   // the late write changes nothing
        #expect(try NotesStore(paths: services.paths).loadNow().notes.first { $0.id == id }?.text == "typed, autosave started")
    }

    @Test func savesReachTheDiskInOrder() async throws {
        let model = await loadedModel()
        let first = model.newNote(text: "first")
        let firstSave = model.saveNow()
        let second = model.newNote(text: "second")
        let secondSave = model.saveNow()
        #expect(model.savesInFlight.count == 2)
        await secondSave?.value
        #expect(model.savesInFlight.isEmpty)                                    // the second waited for the first
        await firstSave?.value
        let reloaded = try NotesStore(paths: services.paths).loadNow()
        #expect(reloaded.notes.map(\.id) == [second, first])
        #expect(reloaded.recovered == 0)
    }

    @Test func failedSavesBackOffAndThenWaitForTheUser() async throws {
        let model = await loadedModel()
        let delays = DelayRecorder()
        model.retrySleep = { try await delays.sleep($0) }
        _ = model.newNote(text: "precious")
        model.autosave.cancel()                                                 // only the saves below
        let notesPath = services.paths.root.appending(path: "notes")
        try FileManager.default.removeItem(at: notesPath)
        try Data("blocker".utf8).write(to: notesPath)                           // every save fails
        model.saveNow()
        try await waitUntil { model.consecutiveSaveFailures == 4 && model.savesInFlight.isEmpty }
        #expect(delays.recorded == [.seconds(5), .seconds(30), .seconds(120)])  // then no more automatic retries
        #expect(model.saveFailed)
        for _ in 0..<50 { await Task.yield() }
        #expect(model.consecutiveSaveFailures == 4)
        try FileManager.default.removeItem(at: notesPath)
        model.panelOpened()                                                     // opening the Nook tries again
        try await waitUntil { !model.saveFailed }
        #expect(try NotesStore(paths: services.paths).loadNow().notes.first?.text == "precious")
        #expect(model.consecutiveSaveFailures == 0)
    }

    @Test func anUnreadableIndexShowsTheErrorAndIsNotOverwritten() async throws {
        let store = NotesStore(paths: services.paths)
        let kept = Note(title: "Kept title", text: "x", mode: .code, language: .swift)
        try store.write(NotesChangeSet(revision: 1, index: NotesIndex(notes: [kept.entry]), texts: [kept.id: "x"]))
        let index = services.paths.root.appending(path: "notes/index.json")
        let path = index.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o000)], ofItemAtPath: path)
        let model = await loadedModel()
        #expect(model.phase == .failed)
        #expect(model.makeChangeSet() == nil)                                   // nothing would replace the index
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: path)
        await model.load()                                                      // "Try again"
        #expect(model.entries.map(\.title) == ["Kept title"])
        #expect(model.entries.first?.language == .swift)
    }

    @Test func theIndexIsNeverWrittenBeforeTheNotesAreLoaded() async throws {
        let store = NotesStore(paths: services.paths)
        let existing = Note(title: "Existing", text: "old", mode: .plain)
        try store.write(NotesChangeSet(revision: 1, index: NotesIndex(notes: [existing.entry]), texts: [existing.id: "old"]))
        let model = makeModel()
        let early = model.newNote(text: "captured at launch")                   // type-to-capture before load
        let change = try #require(model.makeChangeSet())
        #expect(change.index == nil)                                            // would have dropped "Existing"
        #expect(change.texts[early] == "captured at launch")
        try store.write(change)
        await model.load()
        #expect(model.entries.map(\.id) == [early, existing.id])                // early notes stay on top
        let afterLoad = try #require(model.makeChangeSet())
        #expect(afterLoad.index?.notes.map(\.id) == [early, existing.id])
    }

    @Test func recoveredNotesAreTitledFromTheirFirstLine() async throws {
        let store = NotesStore(paths: services.paths)
        try store.write(NotesChangeSet(revision: 1, texts: [UUID(): "## Groceries\nmilk", UUID(): ""]))
        let model = await loadedModel()
        let titles = Set(model.entries.map(\.title))
        #expect(titles == ["Groceries", NotesStrings.untitled])
        #expect(model.makeChangeSet()?.index != nil)                            // the repaired index is saved
    }

    @Test func aFailedLoadShowsTheErrorAndCanBeRetried() async throws {
        let notesPath = services.paths.root.appending(path: "notes")
        try FileManager.default.createDirectory(at: services.paths.root, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: notesPath)                      // the folder can't be created
        let model = await loadedModel()
        #expect(model.phase == .failed)
        try FileManager.default.removeItem(at: notesPath)
        await model.load()
        #expect(model.phase == .loaded)
    }

    @Test func aFailedSaveIsReportedAndKeptForRetry() async throws {
        let model = await loadedModel()
        let id = model.newNote(text: "precious")
        let notesPath = services.paths.root.appending(path: "notes")
        try FileManager.default.removeItem(at: notesPath)
        try Data("blocker".utf8).write(to: notesPath)
        await model.saveNow()?.value
        #expect(model.saveFailed)
        #expect(model.text(of: id) == "precious")
        try FileManager.default.removeItem(at: notesPath)
        await model.saveNow()?.value                                            // the retry
        #expect(!model.saveFailed)
        #expect(try NotesStore(paths: services.paths).loadNow().notes.first?.text == "precious")
    }

    // MARK: Capture, holds, focus mode, opening

    @Test func typeToCaptureStartsANoteWithTheCharacters() async {
        let model = await loadedModel()
        let revision = model.externalRevision
        let widget = model.capture("Hel")
        #expect(widget == .notes)
        #expect(model.selectedEntry.map { model.text(of: $0.id) } == "Hel")
        #expect(model.focusRequested)
        #expect(model.externalRevision > revision)                              // the editor reloads its text
        model.consumeFocusRequest()
        #expect(!model.focusRequested)
    }

    @Test func editingHoldsThePanelOpenOnceAndReleases() {
        let model = makeModel()
        model.editorEditingChanged(true)
        model.editorEditingChanged(true)
        model.editorEditingChanged(false)
        #expect(notch.calls == ["hold(true,notes.editing)", "hold(false,notes.editing)"])
    }

    /// Layout editing or demo redaction while focus mode is shown: the shell may drop focus mode meanwhile, so the
    /// non-live widget releases its holds at once instead of waiting for an explicit close (review of WP5).
    @Test func aWidgetThatStopsBeingLiveReleasesItsHolds() {
        let model = makeModel()
        model.widgetPresentationChanged(isLive: true, isFocusPresented: true)
        model.editorEditingChanged(true)
        #expect(model.isFocusPresented)
        model.widgetPresentationChanged(isLive: false, isFocusPresented: true)  // ⌘E, or redaction turned on
        #expect(!model.isFocusPresented && !model.isEditing)
        #expect(notch.calls.filter { $0.hasPrefix("hold(true") }.count == notch.calls.filter { $0.hasPrefix("hold(false") }.count)
        model.widgetPresentationChanged(isLive: false, isFocusPresented: false) // the shell left focus mode: nothing new
        #expect(notch.calls.count == 4)
        model.widgetPresentationChanged(isLive: true, isFocusPresented: false)
        #expect(!model.isFocusPresented)
    }

    @Test func focusModeHoldsWhilePresentedAndDisappearingReleasesEverything() {
        let model = makeModel()
        model.toggleFocusMode()
        #expect(notch.calls.last == "focus(notes.editor)")
        #expect(model.focusRequested)
        model.focusPresentationChanged(true)
        model.editorEditingChanged(true)
        model.toggleFocusMode()
        #expect(notch.calls.last == "focus(-)")
        model.widgetDisappeared()
        #expect(notch.calls.filter { $0.hasPrefix("hold(true") }.count == notch.calls.filter { $0.hasPrefix("hold(false") }.count)
        #expect(!model.isFocusPresented && !model.isEditing)
    }

    @Test func closingThePanelDropsAnUnusedFocusRequestAndPendingDialogs() async {
        let model = await loadedModel()
        model.newNote(text: "x")                                                // asks for focus
        model.requestDelete()
        model.panelClosed()
        #expect(!model.focusRequested)
        #expect(model.pendingDeletion == nil)
    }

    @Test func revealOpensThePageThatHoldsNotes() async {
        let model = await loadedModel()
        model.reveal()
        #expect(notch.calls.last == "open(-,notes.editor,keyboard)")            // not on any page: no page given
        services.settings[CoreSettings.pages] = [NookPreset.listener.page,
                                                 NookPage(id: "page.focus", symbol: "note.text", items: [.init(.notes, cells: 4)])]
        let id = model.newNote(focus: false)
        model.open(id)
        #expect(notch.calls.last == "open(page.focus,notes.editor,keyboard)")
        #expect(model.selectedID == id)
        #expect(model.focusRequested)
    }
}

/// Records the retry delays a model asks for and returns at once (the backoff runs through in a few turns).
private final class DelayRecorder: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [Duration]())
    var recorded: [Duration] { state.withLock { $0 } }
    @Sendable func sleep(_ duration: Duration) async throws { state.withLock { $0.append(duration) } }
}
