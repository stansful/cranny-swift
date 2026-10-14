// CrannyNotes/Model/NotesModel.swift — the Notes widget's model (ARCHITECTURE.md §10.6): the list of notes, the
// selection, rename/delete flows and the texts. Views observe the list (`entries`); the texts are kept outside
// observation, so typing never re-renders the header or the list. Persistence: NotesModel+Saving.swift;
// shell interaction (holds, focus mode, opening the panel): NotesModel+Shell.swift; the "Automatic" language:
// NotesModel+Language.swift.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.notes)

@MainActor @Observable final class NotesModel {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    /// What the header, the list menu and the sidebar show (no text, so typing does not touch it).
    struct Entry: Identifiable, Equatable {
        var id: UUID
        var title: String
        var mode: NoteMode
        /// The language chosen in the menu; nil = Automatic.
        var language: CodeLanguage?
        /// What Automatic finds for this note in code mode (nil in plain mode or when unsure). Refreshed at most
        /// every 0.4 s while the note changes (`languageDetection`), never per keystroke.
        var detectedLanguage: CodeLanguage? = nil

        /// The language code mode colours the note with.
        var effectiveLanguage: CodeLanguage? { language ?? detectedLanguage }
    }

    private(set) var phase: Phase = .idle
    private(set) var entries: [Entry] = []
    private(set) var selectedID: UUID?
    /// Notes whose text is empty (the editor shows its placeholder); changes only when that flips.
    private(set) var emptyNotes: Set<UUID> = []
    /// The note whose title is being edited in the header.
    var renamingID: UUID?
    /// The note waiting for "Delete" in the inline confirmation.
    private(set) var pendingDeletion: UUID?
    /// The editor should become first responder (new note, type-to-capture, focus mode, ⌘N).
    private(set) var focusRequested = false
    /// Bumped when text changes outside the editor (load, capture): the editor reloads its storage.
    private(set) var externalRevision = 0
    /// The last save failed; the header shows a warning until a save succeeds.
    var saveFailed = false
    /// The editor is first responder in a key panel ("notes.editing" hold).
    var isEditing = false
    /// The Nook shows Notes in focus mode (all columns × 3 rows; "notes.focus" hold).
    var isFocusPresented = false

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let notch: any NotchControl
    @ObservationIgnored let store: NotesStore
    @ObservationIgnored var documents: [UUID: Note] = [:]
    @ObservationIgnored var revision = 0
    @ObservationIgnored var dirtyTexts = Set<UUID>()
    @ObservationIgnored var removedNotes = Set<UUID>()
    @ObservationIgnored var indexDirty = false
    @ObservationIgnored var heldReasons = Set<String>()
    /// The caret/selection of each note, restored when it is shown again (this session only).
    @ObservationIgnored var selections: [UUID: NSRange] = [:]
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored lazy var autosave = CoalescingScheduler { [weak self] in self?.saveNow() }
    /// Notes whose text changed since "Automatic" last looked at them.
    @ObservationIgnored var undetectedNotes = Set<UUID>()
    @ObservationIgnored lazy var languageDetection = CoalescingScheduler(delay: Self.detectionDelay) { [weak self] in
        self?.detectLanguages()
    }
    @ObservationIgnored private let now: () -> Date

    init(settings: SettingsStore, notch: any NotchControl, store: NotesStore, now: @escaping () -> Date = Date.init) {
        self.settings = settings; self.notch = notch; self.store = store; self.now = now
    }

    // MARK: Reading

    var selectedEntry: Entry? { entries.first { $0.id == selectedID } }
    func note(_ id: UUID) -> Note? { documents[id] }
    func text(of id: UUID) -> String { documents[id]?.text ?? "" }
    func entry(_ id: UUID) -> Entry? { entries.first { $0.id == id } }

    /// The language code mode colours a note with ("Automatic" resolved).
    func effectiveLanguage(of id: UUID) -> CodeLanguage? { entry(id)?.effectiveLanguage }

    // MARK: Loading

    /// Reads the folder (off the main actor). Notes created before it finishes (type-to-capture at launch) stay on top.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let result = try await store.load()
            let early = entries.compactMap { documents[$0.id] }
            var loaded = result.notes.filter { documents[$0.id] == nil }
            var titles = Set((early + loaded).map(\.title))
            for i in loaded.indices where loaded[i].title.isEmpty {
                let title = NoteTitles.derived(from: loaded[i].text).map { titles.contains($0) ? uniqueUntitled(titles) : $0 }
                    ?? uniqueUntitled(titles)
                loaded[i].title = title
                titles.insert(title)
            }
            for note in loaded { documents[note.id] = note }
            entries = (early + loaded).map(Self.entry)
            emptyNotes = Set(documents.values.filter { $0.text.isEmpty }.map(\.id))
            if selectedID.flatMap({ documents[$0] }) == nil {
                let last = settings[NotesSettings.lastNoteID].flatMap(UUID.init(uuidString:))
                selectedID = last.flatMap { documents[$0] != nil ? $0 : nil } ?? entries.first?.id
            }
            phase = .loaded
            externalRevision += 1
            if result.recovered > 0 || result.indexWasCorrupt || !early.isEmpty { indexDirty = true; autosave.schedule() }
            log.info("loaded \(self.entries.count, privacy: .public) notes")
        } catch {
            phase = .failed
            log.error("loading notes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Previews and tests: shows `notes` as loaded, without reading or writing anything.
    func adoptLoadedNotes(_ notes: [Note]) {
        for note in notes { documents[note.id] = note }
        entries = notes.map(Self.entry)
        emptyNotes = Set(notes.filter { $0.text.isEmpty }.map(\.id))
        selectedID = notes.first?.id
        phase = .loaded
    }

    /// "Try again" in the error state.
    func reload() { Task { await load() } }

    // MARK: Selection

    func select(_ id: UUID) {
        guard documents[id] != nil else { return }
        if selectedID != id { renamingID = nil; pendingDeletion = nil }
        selectedID = id
        settings[NotesSettings.lastNoteID] = id.uuidString
    }

    /// ⌘] / ⌘[: the next or previous note in the list, wrapping around.
    func selectNext(_ forward: Bool = true) {
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex { $0.id == selectedID } ?? 0
        let next = (index + (forward ? 1 : -1) + entries.count) % entries.count
        select(entries[next].id)
    }

    // MARK: Creating and editing

    /// A new note at the top of the list, in the default mode, selected; the editor takes focus if asked.
    @discardableResult func newNote(text: String = "", focus: Bool = true) -> UUID {
        let date = now()
        let note = Note(title: uniqueUntitled(Set(entries.map(\.title))), text: text,
                        mode: settings[NotesSettings.defaultMode], createdAt: date)
        documents[note.id] = note
        entries.insert(Self.entry(note), at: 0)
        if text.isEmpty { emptyNotes.insert(note.id) }
        selections[note.id] = NSRange(location: (text as NSString).length, length: 0)   // typing continues after it
        renamingID = nil
        pendingDeletion = nil
        select(note.id)
        if focus { focusRequested = true }
        if !text.isEmpty { externalRevision += 1 }
        dirtyTexts.insert(note.id)
        indexDirty = true
        autosave.schedule()
        return note.id
    }

    /// From the editor, after every change of its characters. O(1): no comparison with the previous text (the
    /// editor reports only real changes, and comparing a long note on every keystroke cost milliseconds).
    func setText(_ text: String, for id: UUID) {
        guard var note = documents[id] else { return }
        note.text = text
        note.modifiedAt = now()
        documents[id] = note
        if text.isEmpty != emptyNotes.contains(id) {
            if text.isEmpty { emptyNotes.insert(id) } else { emptyNotes.remove(id) }
        }
        dirtyTexts.insert(id)
        indexDirty = true
        autosave.schedule()
        if note.mode == .code {
            undetectedNotes.insert(id)
            languageDetection.schedule()
        }
    }

    /// A new "Automatic" result (NotesModel+Language.swift): the entry changes only if it differs.
    func setDetectedLanguage(_ language: CodeLanguage?, of id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].detectedLanguage != language else { return }
        entries[index].detectedLanguage = language
    }

    func beginRename() {
        guard let id = selectedID else { return }
        pendingDeletion = nil
        renamingID = id
        notch.requestKeyboardFocus()
    }

    /// Ends a rename: an empty or unchanged title keeps the old one.
    func commitRename(_ proposed: String) {
        guard let id = renamingID else { return }
        renamingID = nil
        guard let title = NoteTitles.sanitized(proposed) else { return }
        update(id) { $0.title = title }
    }

    func setMode(_ mode: NoteMode, for id: UUID) { update(id) { $0.mode = mode } }
    func toggleCodeMode() {
        guard let id = selectedID, let note = documents[id] else { return }
        setMode(note.mode == .code ? .plain : .code, for: id)
    }
    func setLanguage(_ language: CodeLanguage?, for id: UUID) { update(id) { $0.language = language } }

    private func update(_ id: UUID, _ change: (inout Note) -> Void) {
        guard var note = documents[id] else { return }
        let before = note
        change(&note)
        guard note != before else { return }
        documents[id] = note
        if let i = entries.firstIndex(where: { $0.id == id }) { entries[i] = Self.entry(note) }
        indexDirty = true
        autosave.schedule()
    }

    // MARK: Deleting

    func requestDelete() {
        renamingID = nil
        pendingDeletion = selectedID
    }
    func cancelDelete() { pendingDeletion = nil }

    /// Removes the note and selects its neighbour (the next one down, else the one above).
    func confirmDelete() {
        guard let id = pendingDeletion, let index = entries.firstIndex(where: { $0.id == id }) else { pendingDeletion = nil; return }
        pendingDeletion = nil
        entries.remove(at: index)
        documents[id] = nil
        emptyNotes.remove(id)
        dirtyTexts.remove(id)
        removedNotes.insert(id)
        indexDirty = true
        if selectedID == id {
            selectedID = entries.isEmpty ? nil : entries[min(index, entries.count - 1)].id
            settings[NotesSettings.lastNoteID] = selectedID?.uuidString
        }
        autosave.fireNow()                                                      // a delete is saved at once
    }

    // MARK: Type-to-capture and focus

    /// `CaptureTarget.capture`: the first typed characters start a new note with the caret after them.
    func capture(_ characters: String) -> WidgetID {
        newNote(text: characters, focus: true)
        return .notes
    }

    func requestFocus() { focusRequested = true }
    /// The editor took the request (called asynchronously, never during a view update).
    func consumeFocusRequest() { focusRequested = false }

    // MARK: Helpers

    func uniqueUntitled(_ existing: Set<String>) -> String {
        NoteTitles.unique(existing: existing) { $0.map(NotesStrings.untitled) ?? NotesStrings.untitled }
    }

    static func entry(_ note: Note) -> Entry {
        Entry(id: note.id, title: note.title, mode: note.mode, language: note.language, detectedLanguage: detectedLanguage(of: note))
    }
}
