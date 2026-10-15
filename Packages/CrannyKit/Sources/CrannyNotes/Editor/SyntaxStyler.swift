// CrannyNotes/Editor/SyntaxStyler.swift — keeps code mode's colours in the editor's text storage (DESIGN.md §7.5).
// A full pass on a note switch and on a mode, language, title or theme change; after an edit only the lines the
// edit can have changed are tokenized again (`SyntaxCache`) and only the range whose colours changed is restyled
// (`SyntaxHighlighter.changedRange`). No main-actor step grows with the note (DESIGN.md §4.7, no hitches at 120 Hz):
//   • up to `synchronousLimit` UTF-16 units the cache follows each edit right in it (a few lines: ≈ 3 µs in
//     Release; with the attribute writes a keystroke costs 5–40 µs, the growth with the note's length being the
//     text storage's attribute runs). A paste, undo, redo or an edit of more than `wholePassEdit` units tokenizes
//     the whole note again (0.4–0.9 ms at the limit). Longer notes are tokenized off the main actor: the edits of
//     a burst merge into one `TextEdit`, the cache and a snapshot go `@concurrent`, and the result is used only if
//     the text did not change meanwhile (otherwise the pass runs again on the newer text). Until it lands, typed
//     characters show in the base colour;
//   • attributes are written `tokensPerSlice` tokens per main-actor turn (≈ 2 ms): a long restyle colours the
//     note from the top over a few frames instead of freezing one. An edit in between keeps what is already
//     coloured and restyles the rest from the new text.
// `tokens` always lists exactly what the storage shows over the base attributes, which is what `changedRange` needs.
// Only attributes change here: never the characters, so undo is untouched. Inside the storage delegate's
// `didProcessEditing` attributes are set directly (they join the edit being processed); everywhere else the writes
// are grouped in `beginEditing`/`endEditing`. The cache takes only the edited units from the storage's
// `mutableString` (no copy of the whole note per keystroke); the background pass gets its own snapshot.
import AppKit
import Foundation

@MainActor final class SyntaxStyler {
    /// Longer notes are tokenized off the main actor after an edit.
    let synchronousLimit: Int
    /// Tokens whose attributes are written per main-actor turn.
    let tokensPerSlice: Int
    /// The pause between two slices (the run loop draws and handles input meanwhile).
    let pause: Duration
    /// An edit that inserts or removes more UTF-16 units than this tokenizes the whole note again.
    static let wholePassEdit = 1_024

    private weak var storage: NSTextStorage?
    private var attributes: EditorAttributes?
    private(set) var language: CodeLanguage?
    private(set) var isCode = false
    /// The tokens, checkpoints and units of the text the storage's colours were made from (nil: no pass yet).
    private var cache: SyntaxCache?
    /// What the storage shows over the base attributes when that is not `cache.tokens` (an edit cut a sliced
    /// restyle short); valid while there is no backlog.
    private var shown: [SyntaxToken]?
    /// A restyle being written a slice per turn.
    private var backlog: Backlog?
    /// The edits since the cache matched the text, merged (long notes only).
    private var pending: TextEdit?
    /// A paste, undo, redo or large edit is among the pending ones: the background pass tokenizes the whole note.
    private var pendingNeedsWholePass = false
    /// Bumped on every change of the characters: a background result for an older text is dropped.
    private var generation = 0
    private var task: Task<Void, Never>?

    init(synchronousLimit: Int = 32_000, tokensPerSlice: Int = 2_000, pause: Duration = .milliseconds(4)) {
        self.synchronousLimit = synchronousLimit
        self.tokensPerSlice = max(tokensPerSlice, 1)
        self.pause = pause
    }

    /// `cache.tokens[next..<end]` are not written yet: the storage shows the base attributes there.
    private struct Backlog {
        var next: Int
        let end: Int
    }

    /// What the storage shows over the base attributes.
    var tokens: [SyntaxToken] {
        let all = cache?.tokens ?? []
        guard let backlog else { return shown ?? all }
        return Array(all[..<backlog.next]) + all[backlog.end...]
    }
    /// Tokenizing or writing attributes is still to come (tests wait for it).
    var isRestyling: Bool { task != nil }
    /// Edits that tokenized the whole note on the main actor (tests check which ones do).
    private(set) var wholePasses = 0

    func attach(to storage: NSTextStorage) { self.storage = storage }

    /// Colours the whole text again. Drops queued work: it belongs to the old style.
    func restyleAll(code: Bool, language: CodeLanguage?, attributes: EditorAttributes) {
        cancel()
        isCode = code
        self.language = code ? language : nil
        self.attributes = attributes
        cache = nil
        shown = nil
        guard let storage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(attributes.base, range: all)
        guard code, all.length > 0 else { return }
        if all.length <= synchronousLimit {
            cache = SyntaxCache(source: SourceText(storage.mutableString), language: self.language)
            write(over: all)
        } else {
            pending = TextEdit(range: all, delta: 0)                              // everything is new to an empty cache
            pendingNeedsWholePass = true
            startWork()
        }
    }

    /// The characters changed. Called from `NSTextStorageDelegate.textStorage(_:didProcessEditing:…)`, where
    /// attributes may be changed directly (no `beginEditing`: that would process the edit again from inside).
    /// `wholePass`: a paste, undo or redo, tokenized whole like an edit over `wholePassEdit` units.
    func textChanged(_ edit: TextEdit, wholePass: Bool = false) {
        generation += 1
        keepWhatIsWritten()
        guard let storage, let attributes else { return }
        guard isCode else {
            storage.setAttributes(attributes.base, range: edit.range)
            return
        }
        let whole = wholePass || max(edit.range.length, edit.oldEnd - edit.range.location) > Self.wholePassEdit
        if pending == nil && storage.length <= synchronousLimit {
            write(over: update(edit, wholePass: whole, text: storage.mutableString))
        } else {
            storage.setAttributes(attributes.base, range: edit.range)          // until the background pass lands
            pending = pending.map { $0.followed(by: edit) } ?? edit
            pendingNeedsWholePass = pendingNeedsWholePass || whole
            startWork()
        }
    }

    /// Drops queued or running work (note switch, restyle, the editor going away).
    func cancel() {
        task?.cancel()
        task = nil
        if pending != nil { cache = nil }                                       // it no longer matches the text
        pending = nil
        pendingNeedsWholePass = false
        keepWhatIsWritten()
    }

    /// Brings the cache up to `text` (the storage after `edit`); returns the range whose colours differ from what
    /// the storage shows.
    private func update(_ edit: TextEdit, wholePass: Bool, text: NSString) -> NSRange {
        let shownBefore = shown                                                 // nil: the storage shows `cache.tokens`
        shown = nil
        if !wholePass, let change = cache?.apply(edit, from: text), let cache {
            guard let shownBefore else { return cache.changedRange(change, edit: edit) }
            return SyntaxHighlighter.changedRange(old: shownBefore, new: cache.tokens, edit: edit, length: text.length)
        }
        let old = shownBefore ?? cache?.tokens ?? []
        let fresh = SyntaxCache(source: SourceText(text), language: language)
        cache = fresh
        wholePasses += 1
        return SyntaxHighlighter.changedRange(old: old, new: fresh.tokens, edit: edit, length: text.length)
    }

    /// A backlog cut short: the storage keeps the slices already written (`shown`).
    private func keepWhatIsWritten() {
        guard backlog != nil else { return }
        shown = tokens
        backlog = nil
    }

    // MARK: Writing attributes

    /// Shows `cache.tokens` over `span` (outside it the storage already matches them): base over the span at once,
    /// then the tokens in it, a slice now and the rest on later turns.
    private func write(over span: NSRange) {
        guard let storage, let attributes, let fresh = cache?.tokens else { return }
        if span.length > 0 { storage.setAttributes(attributes.base, range: span) }
        let first = Self.firstToken(in: fresh, endingAfter: span.location)
        var end = first
        while end < fresh.count && fresh[end].range.location < NSMaxRange(span) { end += 1 }
        backlog = Backlog(next: first, end: end)
        writeSlice()
    }

    /// Writes the next slice of the backlog; schedules the rest.
    private func writeSlice() {
        guard var backlog, let storage, let attributes, let fresh = cache?.tokens else { return }
        let stop = min(backlog.next + tokensPerSlice, backlog.end)
        if backlog.next < stop {
            for token in fresh[backlog.next..<stop] {
                // Complete dictionaries: `setAttributes` costs about 40 % of `addAttributes` per run.
                storage.setAttributes(attributes.attributes(for: token.kind), range: token.range)
            }
        }
        backlog.next = stop
        if stop < backlog.end {
            self.backlog = backlog
            startWork()
        } else {
            self.backlog = nil
        }
    }

    private static func firstToken(in tokens: [SyntaxToken], endingAfter location: Int) -> Int {
        var low = 0, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(tokens[mid].range) <= location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: Work after the edit (long notes, long restyles)

    private enum Step {
        case tokenize(RestyleJob)
        case writeSlice
    }

    private func startWork() {
        guard task == nil else { return }                                       // the running task loops on
        task = Task { [weak self, pause] in
            while !Task.isCancelled, let step = self?.nextStep() {
                switch step {
                case .tokenize(let job):
                    let result = await SyntaxHighlighter.restyle(job)
                    guard !Task.isCancelled else { return }
                    self?.finish(job, cache: result.cache, changed: result.changed)
                case .writeSlice:
                    try? await Task.sleep(for: pause)                           // a frame and input in between
                    guard !Task.isCancelled else { return }
                    self?.grouped { $0.writeSlice() }
                }
            }
            if !Task.isCancelled { self?.task = nil }
        }
    }

    /// A pending edit first (a backlog never outlives an edit), then the backlog's next slice.
    private func nextStep() -> Step? {
        if let pending, let storage {
            return .tokenize(RestyleJob(source: SourceText(storage.mutableString), language: language, cache: cache,
                                        shown: shown, edit: pending, wholePass: pendingNeedsWholePass,
                                        generation: generation))
        }
        return backlog == nil ? nil : .writeSlice
    }

    /// Uses a background result if the text is still the snapshot it was computed from (else the loop runs
    /// again with the newer pending edit).
    private func finish(_ job: RestyleJob, cache fresh: SyntaxCache, changed: NSRange) {
        guard job.generation == generation, let storage, storage.length == job.source.count else { return }
        pending = nil
        pendingNeedsWholePass = false
        cache = fresh
        shown = nil
        grouped { $0.write(over: changed) }
    }

    /// One `beginEditing`/`endEditing` around writes made outside the storage's own editing.
    private func grouped(_ writes: (SyntaxStyler) -> Void) {
        storage?.beginEditing()
        writes(self)
        storage?.endEditing()
    }
}
