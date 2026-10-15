// CrannyNotes/Editor/SyntaxCache.swift — code mode's tokens of one note, kept across edits (DESIGN.md §7.5, §4.7).
// A pass records a `LexCheckpoint` at every line start its tokenizers reach with nothing open. After an edit they
// resume at the last checkpoint the edit cannot have changed and stop at the first line start past the edit whose
// state equals the old pass's at the same (shifted) place: from there on the old tokens, shifted, are the new ones.
// A keystroke thus costs the lines around it, not the note, and the result is exactly a full pass's
// (`IncrementalLexingTests`). It keeps its own copy of the note's UTF-16 units and takes only the edited ones from
// the text storage. Pure value: no AppKit, no main actor (long notes are updated off it).
import Foundation

nonisolated struct SyntaxCache: Sendable {
    let language: CodeLanguage?
    /// The text the tokens are for.
    private(set) var source: SourceText
    /// Exactly `SyntaxHighlighter.tokens(in: source, language: language)`.
    private(set) var tokens: [SyntaxToken] = []
    /// The line starts the tokenizers passed with nothing open, in order (none above `maximumLength`).
    private(set) var checkpoints: [LexCheckpoint] = []

    /// A full pass over `source`.
    init(source: SourceText, language: CodeLanguage?) {
        self.language = language
        self.source = source
        tokenizeAll()
    }

    /// What one update tokenized again: the old tokens it replaced and where their successors are in `tokens`.
    /// Every other token is the same before and after (moved by the edit's delta when after it).
    struct Change {
        var replaced: [SyntaxToken]
        var inserted: Range<Int>
    }

    /// The range whose colours `change` altered: `SyntaxHighlighter.changedRange` over the re-tokenized tokens only,
    /// which gives the range the whole lists give (the tokens around them lie wholly before or after the edit).
    func changedRange(_ change: Change, edit: TextEdit) -> NSRange {
        SyntaxHighlighter.changedRange(old: change.replaced[...], new: tokens[change.inserted], edited: edit.range,
                                       delta: edit.delta, length: source.count)
    }

    /// `edit` happened in `text` (the text storage after it): the source takes the edited units, then the tokens
    /// follow. A text that does not match the source the cache had is tokenized whole.
    mutating func apply(_ edit: TextEdit, from text: NSString) -> Change {
        let oldEnd = edit.oldEnd
        guard edit.range.location >= 0, edit.range.location <= oldEnd, oldEnd <= source.count,
              source.count + edit.delta == text.length else {
            return replaceAll(with: SourceText(text))
        }
        source.replace(edit.range.location..<oldEnd, with: text, in: edit.range)
        return tokenizeAgain(after: edit)
    }

    /// `edit` (a burst of edits, merged) turned the text into `newSource`.
    mutating func apply(_ edit: TextEdit, source newSource: SourceText) -> Change {
        guard source.count + edit.delta == newSource.count else { return replaceAll(with: newSource) }
        source = newSource
        return tokenizeAgain(after: edit)
    }

    /// A full pass over `newSource` (a paste, undo or redo, a large edit): every old token counts as replaced.
    mutating func replaceAll(with newSource: SourceText) -> Change {
        let replaced = tokens
        source = newSource
        tokenizeAll()
        return Change(replaced: replaced, inserted: 0..<tokens.count)
    }

    // MARK: Passes

    private mutating func tokenizeAll() {
        guard source.count <= SyntaxHighlighter.maximumLength else {
            tokens = []
            checkpoints = []
            return
        }
        var sink = TokenSink(recording: true)
        SyntaxHighlighter.tokenize(source, in: 0..<source.count, language: language, depth: 0, into: &sink)
        tokens = sink.tokens
        checkpoints = sink.checkpoints
    }

    /// The source already holds the text after `edit`; the tokens and checkpoints still describe the text before it.
    private mutating func tokenizeAgain(after edit: TextEdit) -> Change {
        let limit = SyntaxHighlighter.maximumLength
        guard source.count <= limit, source.count - edit.delta <= limit else { return replaceAll(with: source) }
        let start = edit.range.location
        var resume = firstCheckpoint(atOrAfter: start) - 1
        while resume >= 0 && !canResume(at: checkpoints[resume], before: start) { resume -= 1 }
        let checkpoint = resume >= 0 ? checkpoints[resume] : nil
        let from = checkpoint?.position ?? 0
        let pass = resumedPass(at: checkpoint, metFrom: resume + 1, edit: edit)
        // Tokens never straddle a checkpoint: those before `from` stay, those from the met checkpoint on move.
        let first = firstToken(endingAfter: from)
        var last = tokens.count
        var lastCheckpoint = checkpoints.count
        if let met = pass.met {
            last = firstToken(endingAfter: checkpoints[met].position, from: first)
            lastCheckpoint = met + 1
        }
        let replaced = Array(tokens[first..<last])
        tokens.replaceSubrange(first..<last, with: pass.tokens)
        let inserted = first..<(first + pass.tokens.count)
        checkpoints.replaceSubrange((resume + 1)..<lastCheckpoint, with: pass.checkpoints)
        if edit.delta != 0 {
            for i in inserted.upperBound..<tokens.count { tokens[i].range.location += edit.delta }
            for i in (resume + 1 + pass.checkpoints.count)..<checkpoints.count { checkpoints[i].position += edit.delta }
        }
        return Change(replaced: replaced, inserted: inserted)
    }

    /// The tokenizers resumed at `checkpoint` (nil: from the start) over the new source, stopped at the first
    /// checkpoint past the edit equal to the old one at the same shifted place (`met`, an index in `checkpoints`).
    /// A function of its own so the sink's reference to the old checkpoints is gone before they are replaced.
    private func resumedPass(at checkpoint: LexCheckpoint?, metFrom index: Int, edit: TextEdit)
        -> (tokens: [SyntaxToken], checkpoints: [LexCheckpoint], met: Int?) {
        var sink = TokenSink(resuming: checkpoint, old: checkpoints, from: index, delta: edit.delta,
                             unchangedFrom: NSMaxRange(edit.range))
        SyntaxHighlighter.tokenize(source, in: (checkpoint?.position ?? 0)..<source.count, language: language, depth: 0,
                                   resuming: checkpoint?.state, into: &sink)
        return (sink.tokens, sink.checkpoints, sink.met)
    }

    /// A pass may resume at `checkpoint` after an edit at `start` when the checkpoint and every look made before it
    /// lie before the edit and, inside a fence or `<script>` body, so does its own line: that line decides whether
    /// the body goes on past it (a closing fence there would end it before the checkpoint).
    private func canResume(at checkpoint: LexCheckpoint, before start: Int) -> Bool {
        guard checkpoint.position + checkpoint.reach < start else { return false }
        return checkpoint.state.count < 2 || source.lineEnd(from: checkpoint.position) < start
    }

    // MARK: Searches

    /// The index of the first checkpoint at or after `position`.
    private func firstCheckpoint(atOrAfter position: Int) -> Int {
        var low = 0, high = checkpoints.count
        while low < high {
            let mid = (low + high) / 2
            if checkpoints[mid].position < position { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The index of the first token from `lower` on that ends after `position`.
    private func firstToken(endingAfter position: Int, from lower: Int = 0) -> Int {
        var low = lower, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(tokens[mid].range) <= position { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
