// CrannyNotes/Editor/SyntaxHighlighter.swift — code mode's pure tokenizer front door (DESIGN.md §7.5): picks the
// tokenizer for a language and works out the smallest range whose colours an edit changed, so typing in a
// long note restyles a few characters instead of the whole document. The editor keeps its tokens in a
// `SyntaxCache`, which re-tokenizes only the lines an edit can have changed. No AppKit; unit-tested per language.
import Foundation

nonisolated enum SyntaxHighlighter {
    /// Longer notes are shown without colours (typing stays smooth; the text itself is unaffected).
    static let maximumLength = 300_000

    /// Sorted, non-overlapping tokens for `text`. `language == nil` = unknown code (strings, numbers, comments).
    static func tokens(in text: String, language: CodeLanguage?) -> [SyntaxToken] {
        tokens(in: SourceText(text), language: language)
    }

    static func tokens(in source: SourceText, language: CodeLanguage?) -> [SyntaxToken] {
        guard source.count <= maximumLength else { return [] }
        var sink = TokenSink()
        tokenize(source, in: 0..<source.count, language: language, depth: 0, into: &sink)
        return sink.tokens
    }

    /// Appends the tokens of `range` (a fence body, a `<script>`) to `sink`. `depth` limits nesting. `state`: the
    /// range starts at a checkpoint where this tokenizer (and those it nests) were in that state.
    static func tokenize(_ source: SourceText, in range: Range<Int>, language: CodeLanguage?, depth: Int,
                         resuming state: LexState? = nil, into sink: inout TokenSink) {
        switch language {
        case .markdown?: MarkdownTokenizer(depth: depth).tokenize(source, in: range, resuming: state, into: &sink)
        case .json?: JSONTokenizer().tokenize(source, in: range, into: &sink)
        case .yaml?: YAMLTokenizer().tokenize(source, in: range, resuming: state, into: &sink)
        case .html?: MarkupTokenizer(depth: depth).tokenize(source, in: range, resuming: state, into: &sink)
        case .css?: StyleSheetTokenizer().tokenize(source, in: range, resuming: state, into: &sink)
        case let language?:
            CodeTokenizer(spec: LanguageSpec.spec(for: language) ?? .generic).tokenize(source, in: range, into: &sink)
        case nil:
            CodeTokenizer(spec: .generic).tokenize(source, in: range, into: &sink)
        }
    }

    // MARK: Incremental restyling

    /// The range whose styling differs between `old` (tokens before an edit) and `new` (tokens after it).
    ///
    /// `edited` is the edited range in the NEW text and `delta` the change in length, as `NSTextStorage`
    /// reports them. Tokens before the edit keep their place, tokens after it move by `delta`; the result
    /// covers the edit plus every token that is not the same in both lists. Outside it, the storage's
    /// existing attributes are already right, so only this range needs restyling.
    ///
    /// `SyntaxCache` passes only the tokens it re-tokenized (`SyntaxCache.Change`): the tokens around them are the
    /// same in both lists and lie wholly before or after the edit, so the result is the one the whole lists give.
    static func changedRange(old: [SyntaxToken], new: [SyntaxToken], edit: TextEdit, length: Int) -> NSRange {
        changedRange(old: old[...], new: new[...], edited: edit.range, delta: edit.delta, length: length)
    }

    static func changedRange(old: [SyntaxToken], new: [SyntaxToken], edited: NSRange, delta: Int, length: Int) -> NSRange {
        changedRange(old: old[...], new: new[...], edited: edited, delta: delta, length: length)
    }

    static func changedRange(old: ArraySlice<SyntaxToken>, new: ArraySlice<SyntaxToken>, edited: NSRange, delta: Int,
                             length: Int) -> NSRange {
        let editStart = edited.location
        let oldEditEnd = edited.location + edited.length - delta              // end of the replaced range, old coords
        func shifted(_ token: SyntaxToken) -> SyntaxToken? {                   // nil: the token touched the edit
            if NSMaxRange(token.range) <= editStart { return token }
            if token.range.location >= oldEditEnd {
                return SyntaxToken(token.kind, NSRange(location: token.range.location + delta, length: token.range.length))
            }
            return nil
        }
        let o = old.startIndex, n = new.startIndex                            // slices keep their parents' indices
        var prefix = 0
        while prefix < old.count && prefix < new.count, let moved = shifted(old[o + prefix]), moved == new[n + prefix],
              NSMaxRange(moved.range) <= editStart {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix && suffix < new.count - prefix {
            let oldToken = old[old.endIndex - 1 - suffix], newToken = new[new.endIndex - 1 - suffix]
            guard let moved = shifted(oldToken), moved == newToken, moved.range.location >= NSMaxRange(edited) else { break }
            suffix += 1
        }
        var lower = editStart
        var upper = NSMaxRange(edited)
        func include(_ range: NSRange) {
            lower = min(lower, range.location)
            upper = max(upper, NSMaxRange(range))
        }
        for token in new[(n + prefix)..<(new.endIndex - suffix)] { include(token.range) }
        // Old tokens in new coordinates: before the edit unchanged, after it moved, inside it clamped to the edit.
        let newEditEnd = NSMaxRange(edited)
        func map(_ p: Int, inside: Int) -> Int { p <= editStart ? p : (p >= oldEditEnd ? p + delta : inside) }
        for token in old[(o + prefix)..<(old.endIndex - suffix)] {
            let start = map(token.range.location, inside: editStart)
            let end = map(NSMaxRange(token.range), inside: newEditEnd)
            include(NSRange(location: start, length: max(end - start, 0)))
        }
        lower = min(max(lower, 0), length)
        upper = min(max(upper, lower), length)
        return NSRange(location: lower, length: upper - lower)
    }
}

// MARK: - Off the main actor

/// A long note's restyle after `edit` (all edits since `cache` was made, merged): the snapshot to tokenize, the
/// cache to bring up to it and what the storage shows now (`shown`, nil when that is `cache.tokens`). `wholePass`:
/// a paste, undo, redo or large edit is among them. `generation` tells the styler whether the text changed while
/// this ran.
nonisolated struct RestyleJob: Sendable {
    var source: SourceText
    var language: CodeLanguage?
    var cache: SyntaxCache?
    var shown: [SyntaxToken]?
    var edit: TextEdit
    var wholePass: Bool
    var generation: Int
}

extension SyntaxHighlighter {
    /// The cache for the snapshot and the range whose colours differ from what the storage shows, computed off the
    /// main actor.
    @concurrent static func restyle(_ job: RestyleJob) async -> (cache: SyntaxCache, changed: NSRange) {
        let length = job.source.count
        guard var cache = job.cache, cache.language == job.language, !job.wholePass else {
            let cache = SyntaxCache(source: job.source, language: job.language)
            let old = job.shown ?? job.cache?.tokens ?? []
            return (cache, changedRange(old: old, new: cache.tokens, edit: job.edit, length: length))
        }
        let change = cache.apply(job.edit, source: job.source)
        guard let shown = job.shown else { return (cache, cache.changedRange(change, edit: job.edit)) }
        return (cache, changedRange(old: shown, new: cache.tokens, edit: job.edit, length: length))
    }
}
