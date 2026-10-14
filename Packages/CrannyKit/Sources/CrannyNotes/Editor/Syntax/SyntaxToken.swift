// CrannyNotes/Editor/Syntax/SyntaxToken.swift — the output of the code-mode tokenizers (DESIGN.md §7.5) and the
// UTF-16 source buffer they scan. Pure values: no AppKit, no main actor, unit-tested per language.
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
    let units: [UInt16]
    var count: Int { units.count }

    init(_ string: String) { units = Array(string.utf16) }

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

/// Accumulates tokens in order, dropping empty runs. Every tokenizer writes into one of these.
nonisolated struct TokenSink {
    private(set) var tokens: [SyntaxToken] = []

    mutating func add(_ kind: SyntaxKind, _ range: Range<Int>) {
        guard !range.isEmpty else { return }
        tokens.append(SyntaxToken(kind, range))
    }

    mutating func append(contentsOf other: [SyntaxToken]) { tokens.append(contentsOf: other) }
}
