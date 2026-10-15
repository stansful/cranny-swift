// CrannyNotes/Editor/Syntax/SyntaxToken.swift — the output of the code-mode tokenizers (DESIGN.md §7.5), the
// UTF-16 source buffer they scan and the sink they write tokens and resume points (`LexCheckpoint`) into. Pure
// values: no AppKit, no main actor, unit-tested per language.
import Foundation

/// What a run of characters is, for colouring. The colours come from `SyntaxPalette` (DESIGN.md §2.1):
/// comments are `tertiaryLabel` italic, headings `label` semibold, markers (Markdown punctuation) tertiary.
nonisolated enum SyntaxKind: String, Sendable, CaseIterable {
    case keyword, type, string, number, function, link
    case comment
    /// Markdown heading text.
    case heading
    /// Markdown `*emphasis*` (italic) and `**strong**` (semibold).
    case emphasis, strong
    /// Markdown inline code and the body of a fence without a known language.
    case code
    /// Markdown punctuation (`#`, `>`, list bullets, fence lines, `**`): dimmed so the prose stands out.
    case marker
}

/// One coloured run. `range` is in UTF-16 code units, so it maps 1:1 onto `NSRange` in the text storage.
nonisolated struct SyntaxToken: Equatable, Sendable, CustomStringConvertible {
    var kind: SyntaxKind
    var range: NSRange

    init(_ kind: SyntaxKind, _ range: NSRange) { self.kind = kind; self.range = range }
    init(_ kind: SyntaxKind, _ range: Range<Int>) { self.init(kind, NSRange(location: range.lowerBound, length: range.count)) }

    var description: String { "\(kind.rawValue)@\(range.location)+\(range.length)" }
}

/// The text being tokenized, as UTF-16 code units (the unit `NSString`/`NSTextStorage` ranges count in).
/// Identifiers outside ASCII (Cyrillic names, emoji) count as identifier characters so they never split words.
nonisolated struct SourceText: Sendable {
    private(set) var units: [UInt16]
    var count: Int { units.count }

    init(_ string: String) { units = Array(string.utf16) }

    /// One `getCharacters` copy: much faster than walking a `String` bridged from the text storage.
    init(_ string: NSString) {
        units = Self.units(of: string, in: NSRange(location: 0, length: string.length))
    }

    /// Replaces `range` with the units of `string` in `replacement` (the text after an edit, read only where it
    /// changed: no copy of the whole note per keystroke).
    mutating func replace(_ range: Range<Int>, with string: NSString, in replacement: NSRange) {
        units.replaceSubrange(range, with: Self.units(of: string, in: replacement))
    }

    private static func units(of string: NSString, in range: NSRange) -> [UInt16] {
        [UInt16](unsafeUninitializedCapacity: range.length) { buffer, initialized in
            if let base = buffer.baseAddress { string.getCharacters(base, range: range) }
            initialized = range.length
        }
    }

    subscript(_ index: Int) -> UInt16 { index >= 0 && index < units.count ? units[index] : 0 }

    func string(_ range: Range<Int>) -> String {
        let clamped = max(range.lowerBound, 0)..<min(range.upperBound, units.count)
        guard !clamped.isEmpty else { return "" }
        return String(decoding: units[clamped], as: UTF16.self)
    }

    /// `literal` (ASCII) starts at `index`.
    func matches(_ literal: String, at index: Int, caseInsensitive: Bool = false) -> Bool {
        var i = index
        for scalar in literal.utf16 {
            guard i < units.count else { return false }
            let unit = units[i]
            if unit != scalar && !(caseInsensitive && Self.lowercased(unit) == Self.lowercased(scalar)) { return false }
            i += 1
        }
        return true
    }

    /// First index ≥ `index` where `literal` starts, or nil.
    func find(_ literal: String, from index: Int, until end: Int? = nil) -> Int? {
        let limit = min(end ?? units.count, units.count)
        guard let first = literal.utf16.first else { return nil }
        var i = max(index, 0)
        while i < limit {
            if units[i] == first && matches(literal, at: i) { return i }
            i += 1
        }
        return nil
    }

    /// End of the line containing `index` (the index of the newline, or `count`).
    func lineEnd(from index: Int) -> Int {
        var i = max(index, 0)
        while i < units.count && !Self.isNewline(units[i]) { i += 1 }
        return i
    }

    /// End of the identifier that starts at `index`.
    func identifierEnd(from index: Int) -> Int {
        var i = index
        while i < units.count && Self.isIdentifierPart(units[i]) { i += 1 }
        return i
    }

    /// The next index ≥ `index` that is not a space or tab (newlines stop the search).
    func skipSpaces(from index: Int, until end: Int? = nil) -> Int {
        let limit = min(end ?? units.count, units.count)
        var i = index
        while i < limit && Self.isSpace(units[i]) { i += 1 }
        return i
    }

    // MARK: Character classes (UTF-16 units)

    static func isNewline(_ c: UInt16) -> Bool { c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 }
    static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 }
    static func isWhitespace(_ c: UInt16) -> Bool { isSpace(c) || isNewline(c) || c == 0x0B || c == 0x0C }
    static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isHexDigit(_ c: UInt16) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
    static func isUpper(_ c: UInt16) -> Bool { c >= 0x41 && c <= 0x5A }
    static func isLetter(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    static func isIdentifierStart(_ c: UInt16) -> Bool { isLetter(c) || c == 0x5F || (c >= 0x80 && !isNewline(c) && c != 0xA0) }
    static func isIdentifierPart(_ c: UInt16) -> Bool { isIdentifierStart(c) || isDigit(c) }
    static func lowercased(_ c: UInt16) -> UInt16 { isUpper(c) ? c + 0x20 : c }

    static let backslash: UInt16 = 0x5C
}

// MARK: - Token collection

/// Accumulates tokens in order, dropping empty runs. Every tokenizer writes into one of these and, when the sink
/// records, reports each line start its loop reaches with nothing open (`checkpoint`), so `SyntaxCache` can resume
/// there. A resumed pass compares each new checkpoint past the edit with the old pass's at the same shifted place
/// and stops all tokenizers at the first equal one (`isStopped`): from there the old tokens are the new ones.
nonisolated struct TokenSink {
    private(set) var tokens: [SyntaxToken] = []
    /// The line starts passed with nothing open (empty unless the sink records).
    private(set) var checkpoints: [LexCheckpoint] = []
    /// Set at the first checkpoint equal to the old pass's: every tokenizer returns without another token.
    private(set) var isStopped = false
    /// The index in the old checkpoints of the one this pass met.
    private(set) var met: Int?
    /// The end of the furthest line a decision so far looked at ahead of the scan (`read(upTo:)`).
    private(set) var horizon = 0

    private let records: Bool
    /// The levels of the tokenizers around the one running (a fence's, a `<script>`'s); `overflow` counts levels
    /// past `LexState.capacity`, inside which nothing is recorded.
    private var context = LexState()
    private var overflow = 0
    /// Where a resumed pass started: its own line start is not recorded again.
    private var resumedAt = 0
    /// A resumed pass: the old pass's checkpoints from `next` on, the edit's change in length, and the first new
    /// position whose text the edit left alone.
    private var old: [LexCheckpoint] = []
    private var next = 0
    private var delta = 0
    private var meetsFrom = Int.max

    /// Tokens only.
    init() { records = false }

    /// Tokens and checkpoints of a pass from the start of the text.
    init(recording: Bool) { records = recording }

    /// A pass resumed at `checkpoint` (nil: from the start) after an edit that changed the length by `delta` and
    /// left the text from `unchangedFrom` on as it was: it stops at a checkpoint equal to one of `old` from `index`.
    init(resuming checkpoint: LexCheckpoint?, old: [LexCheckpoint], from index: Int, delta: Int, unchangedFrom: Int) {
        records = true
        resumedAt = checkpoint?.position ?? 0
        horizon = checkpoint.map { $0.position + $0.reach } ?? 0
        self.old = old
        next = index
        self.delta = delta
        meetsFrom = unchangedFrom
    }

    mutating func add(_ kind: SyntaxKind, _ range: Range<Int>) {
        guard !range.isEmpty else { return }
        tokens.append(SyntaxToken(kind, range))
    }

    /// A decision looked as far as `position`, ahead of where the scan is (it moves the reach of later checkpoints).
    /// It counts as reading to the end of that line: the rest of the line decides whether the tokenizer's range ends
    /// at or before `position` (a fence's closing line, a `</style>`), which would have cut the look short. A look
    /// that got to the range's `end` likewise counts as reading the line `end` is on.
    /// A look short of the horizon cannot move it (the horizon is a line end, or the line start the pass began at,
    /// which every look is at or after), so a line is scanned once: a minified JSON or CSS line, with a look per
    /// string or declaration, stays linear. Only a recording pass keeps a horizon.
    mutating func read(upTo position: Int, end: Int, in s: SourceText) {
        let reached = min(position, end)
        guard records, reached >= horizon else { return }
        horizon = s.lineEnd(from: reached)
    }

    /// A tokenizer for a nested body (a fence's, a `<script>`'s) starts inside `level`.
    mutating func enter(_ level: LexLevel) {
        if overflow == 0, let state = context.appending(level) { context = state } else { overflow += 1 }
    }

    /// The nested body's tokenizer returned.
    mutating func leave() {
        if overflow > 0 { overflow -= 1 } else { context = context.droppingLast() }
    }

    /// The running tokenizer's loop is at `position` with nothing open and `level` carried into it. Recorded when it
    /// is a line start (a CR's LF is no line start) inside the tokenizer's range (`end` excluded).
    @inline(__always)
    mutating func checkpoint(_ s: SourceText, at position: Int, before end: Int, _ level: LexLevel) {
        guard records, position < end, position > resumedAt else { return }
        let previous = s[position - 1]
        guard SourceText.isNewline(previous), !(previous == 0x0D && s[position] == 0x0A) else { return }
        record(position, level)
    }

    private mutating func record(_ position: Int, _ level: LexLevel) {
        guard overflow == 0, let state = context.appending(level) else { return }
        let point = LexCheckpoint(position: position, state: state, reach: max(horizon - position, 0))
        checkpoints.append(point)
        guard position >= meetsFrom else { return }
        let target = position - delta
        while next < old.count && old[next].position < target { next += 1 }
        if next < old.count && old[next].position == target && old[next].state == state && old[next].reach == point.reach {
            met = next
            isStopped = true
        }
    }
}
