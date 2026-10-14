// CrannyNotes/Editor/SyntaxStyler.swift — keeps code mode's colours in the editor's text storage (DESIGN.md §7.5).
// A full pass on a note switch and on a mode, language, title or theme change; after an edit only the range whose
// colours changed is restyled (`SyntaxHighlighter.changedRange`). No main-actor step grows with the note
// (DESIGN.md §4.7, no hitches at 120 Hz):
//   • up to `synchronousLimit` UTF-16 units a note is tokenized again right in the edit (≈ 1 ms in Release);
//     longer notes are tokenized off the main actor: the edits of a burst merge into one `TextEdit`, a snapshot
//     is tokenized `@concurrent`, and the result is used only if the text did not change meanwhile (otherwise
//     the pass runs again on the newer text). Until it lands, typed characters show in the base colour;
//   • attributes are written `tokensPerSlice` tokens per main-actor turn (≈ 2 ms): a long restyle colours the
//     note from the top over a few frames instead of freezing one. An edit in between keeps what is already
//     coloured and restyles the rest from the new text.
// `tokens` (or the backlog's `shown`) always lists exactly what the storage shows over the base attributes, which
// is what `changedRange` needs. Only attributes change here: never the characters, so undo is untouched. Inside
// the storage delegate's `didProcessEditing` attributes are set directly (they join the edit being processed);
// everywhere else the writes are grouped in `beginEditing`/`endEditing`. The tokenizer reads the storage through
// `mutableString` (no `String` copy of the whole note per keystroke); the background pass gets its own snapshot.
import AppKit
import Foundation

@MainActor final class SyntaxStyler {
    /// Longer notes are tokenized off the main actor after an edit.
    let synchronousLimit: Int
    /// Tokens whose attributes are written per main-actor turn.
    let tokensPerSlice: Int
    /// The pause between two slices (the run loop draws and handles input meanwhile).
    let pause: Duration

    private weak var storage: NSTextStorage?
    private var attributes: EditorAttributes?
    private(set) var language: CodeLanguage?
    private(set) var isCode = false
    /// What the storage shows over the base attributes (valid while there is no backlog).
    private var applied: [SyntaxToken] = []
    /// A restyle being written a slice per turn.
    private var backlog: Backlog?
    /// The edits since `applied` matched the text, merged (long notes only).
    private var pending: TextEdit?
    /// Bumped on every change of the characters: a background result for an older text is dropped.
    private var generation = 0
    private var task: Task<Void, Never>?

    init(synchronousLimit: Int = 32_000, tokensPerSlice: Int = 2_000, pause: Duration = .milliseconds(4)) {
        self.synchronousLimit = synchronousLimit
        self.tokensPerSlice = max(tokensPerSlice, 1)
        self.pause = pause
    }

    private struct Backlog {
        /// The tokens of the whole text; those of `next..<end` are not written yet.
        let fresh: [SyntaxToken]
        var next: Int
        let end: Int
        /// What the storage shows now.
        var shown: [SyntaxToken] { Array(fresh[..<next]) + fresh[end...] }
    }

    /// What the storage shows over the base attributes.
    var tokens: [SyntaxToken] { backlog?.shown ?? applied }
    /// Tokenizing or writing attributes is still to come (tests wait for it).
    var isRestyling: Bool { task != nil }

    func attach(to storage: NSTextStorage) { self.storage = storage }

    /// Colours the whole text again. Drops queued work: it belongs to the old style.
    func restyleAll(code: Bool, language: CodeLanguage?, attributes: EditorAttributes) {
        cancel()
        isCode = code
        self.language = code ? language : nil
        self.attributes = attributes
        guard let storage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(attributes.base, range: all)
        applied = []
        guard code, all.length > 0 else { return }
        if all.length <= synchronousLimit {
            write(SyntaxHighlighter.tokens(in: SourceText(storage.mutableString), language: self.language), over: all)
        } else {
            pending = TextEdit(range: all, delta: 0)                              // everything is new to `applied` = []
            startWork()
        }
    }

    /// The characters changed. Called from `NSTextStorageDelegate.textStorage(_:didProcessEditing:…)`, where
    /// attributes may be changed directly (no `beginEditing`: that would process the edit again from inside).
    func textChanged(_ edit: TextEdit) {
        generation += 1
        if let backlog {                                                        // keep what is written, redo the rest
            applied = backlog.shown
            self.backlog = nil
        }
        guard let storage, let attributes else { return }
        guard isCode else {
            storage.setAttributes(attributes.base, range: edit.range)
            return
        }
        if pending == nil && storage.length <= synchronousLimit {
            let fresh = SyntaxHighlighter.tokens(in: SourceText(storage.mutableString), language: language)
            write(fresh, over: SyntaxHighlighter.changedRange(old: applied, new: fresh, edit: edit, length: storage.length))
        } else {
            storage.setAttributes(attributes.base, range: edit.range)          // until the background pass lands
            pending = pending.map { $0.followed(by: edit) } ?? edit
            startWork()
        }
    }

    /// Drops queued or running work (note switch, restyle, the editor going away).
    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
        if let backlog {
            applied = backlog.shown
            self.backlog = nil
        }
    }

    // MARK: Writing attributes

    /// Shows `fresh` over `span` (outside it the storage already matches `fresh`): base over the span at once,
    /// then the tokens in it, a slice now and the rest on later turns.
    private func write(_ fresh: [SyntaxToken], over span: NSRange) {
        guard let storage, let attributes else { return }
        if span.length > 0 { storage.setAttributes(attributes.base, range: span) }
        let first = Self.firstToken(in: fresh, endingAfter: span.location)
        var end = first
        while end < fresh.count && fresh[end].range.location < NSMaxRange(span) { end += 1 }
        backlog = Backlog(fresh: fresh, next: first, end: end)
        writeSlice()
    }

    /// Writes the next slice of the backlog; schedules the rest.
    private func writeSlice() {
        guard var backlog, let storage, let attributes else { return }
        let stop = min(backlog.next + tokensPerSlice, backlog.end)
        if backlog.next < stop {
            for token in backlog.fresh[backlog.next..<stop] {
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
            applied = backlog.fresh
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
                    self?.finish(job, tokens: result.tokens, changed: result.changed)
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
            return .tokenize(RestyleJob(source: SourceText(storage.mutableString), language: language, old: applied,
                                        edit: pending, generation: generation))
        }
        return backlog == nil ? nil : .writeSlice
    }

    /// Uses a background result if the text is still the snapshot it was computed from (else the loop runs
    /// again with the newer pending edit).
    private func finish(_ job: RestyleJob, tokens fresh: [SyntaxToken], changed: NSRange) {
        guard job.generation == generation, let storage, storage.length == job.source.count else { return }
        pending = nil
        grouped { $0.write(fresh, over: changed) }
    }

    /// One `beginEditing`/`endEditing` around writes made outside the storage's own editing.
    private func grouped(_ writes: (SyntaxStyler) -> Void) {
        storage?.beginEditing()
        writes(self)
        storage?.endEditing()
    }
}
