// CrannyNotes/Editor/Syntax/CodeTokenizer.swift — one table-driven scanner for every C-like and scripting language
// (`LanguageSpec`). A single left-to-right pass; tokens come out sorted and never overlap.
import Foundation

nonisolated struct CodeTokenizer {
    /// The language's table. A tokenizer is made for every pass (each keystroke, each fence), so it keeps nothing
    /// else: the spec's word sets are built once (a case-insensitive spec lists its keywords in lowercase).
    let spec: LanguageSpec

    private enum ASCII {
        static let quote: UInt16 = 0x22, apostrophe: UInt16 = 0x27, hash: UInt16 = 0x23, dollar: UInt16 = 0x24
        static let at: UInt16 = 0x40, colon: UInt16 = 0x3A, dot: UInt16 = 0x2E, openParen: UInt16 = 0x28
        static let openBracket: UInt16 = 0x5B, closeBracket: UInt16 = 0x5D, openBrace: UInt16 = 0x7B
        static let closeBrace: UInt16 = 0x7D, bang: UInt16 = 0x21, question: UInt16 = 0x3F, less: UInt16 = 0x3C
        static let greater: UInt16 = 0x3E, underscore: UInt16 = 0x5F
    }

    func tokenize(_ source: SourceText, in range: Range<Int>, into sink: inout TokenSink) {
        var i = range.lowerBound
        let end = min(range.upperBound, source.count)
        var atLineStart = true
        while i < end {
            let c = source[i]
            if SourceText.isNewline(c) { atLineStart = true; i += 1; continue }
            if SourceText.isWhitespace(c) { i += 1; continue }
            let lineStart = atLineStart
            atLineStart = false
            if let next = comment(source, at: i, end: end, sink: &sink)
                ?? string(source, at: i, end: end, sink: &sink)
                ?? number(source, at: i, end: end, sink: &sink)
                ?? prefixed(source, at: i, end: end, lineStart: lineStart, sink: &sink)
                ?? identifier(source, at: i, end: end, sink: &sink) {
                i = max(next, i + 1)
            } else {
                i += 1
            }
        }
    }

    // MARK: Comments

    private func comment(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        if let block = spec.blockComment, s.matches(block.open, at: i) {
            let close = blockCommentEnd(s, from: i + block.open.utf16.count, end: end, block: block)
            sink.add(.comment, i..<close)
            return close
        }
        guard spec.lineComments.contains(where: { s.matches($0, at: i) }) else { return nil }
        if spec.lineCommentNeedsBoundary && i > 0 && !SourceText.isWhitespace(s[i - 1]) { return nil }
        let lineEnd = min(s.lineEnd(from: i), end)
        sink.add(.comment, i..<lineEnd)
        return lineEnd
    }

    private func blockCommentEnd(_ s: SourceText, from start: Int, end: Int, block: LanguageSpec.Delimited) -> Int {
        var depth = 1
        var j = start
        while j < end {
            if spec.nestedBlockComments && s.matches(block.open, at: j) {
                depth += 1; j += block.open.utf16.count
            } else if s.matches(block.close, at: j) {
                depth -= 1; j += block.close.utf16.count
                if depth == 0 { return j }
            } else {
                j += 1
            }
        }
        return end
    }

    // MARK: Strings

    private func string(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        if spec.rust && s[i] == ASCII.apostrophe { return rustQuote(s, at: i, end: end, sink: &sink) }
        if spec.stringPrefixes.contains("@") && s[i] == ASCII.at && s[i + 1] == ASCII.quote,
           let close = delimited(s, at: i + 1, end: end) {
            sink.add(.string, i..<close)
            return close
        }
        guard let close = delimited(s, at: i, end: end) else { return nil }
        sink.add(.string, i..<close)
        return close
    }

    /// The end of a string that opens at `i` with one of the spec's delimiters, or nil.
    func delimited(_ s: SourceText, at i: Int, end: Int) -> Int? {
        guard let rule = spec.strings.first(where: { s.matches($0.open, at: i) }) else { return nil }
        return Self.scan(s, rule: rule, from: i + rule.open.utf16.count, end: end)
    }

    /// Scans a string body to just past its closing delimiter; unterminated strings stop at the line end
    /// (single-line rules) or at `end`.
    static func scan(_ s: SourceText, rule: LanguageSpec.Delimited, from start: Int, end: Int) -> Int {
        var j = start
        while j < end {
            let u = s[j]
            if rule.escapes && u == SourceText.backslash { j += 2; continue }
            if !rule.multiline && SourceText.isNewline(u) { return j }
            if s.matches(rule.close, at: j) { return j + rule.close.utf16.count }
            j += 1
        }
        return min(j, end)
    }

    /// Rust: `'x'`, `'\n'` and `'\u{1F600}'` are characters; `'a` (no closing quote) is a lifetime.
    private func rustQuote(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        if s[i + 1] == SourceText.backslash {
            let lineEnd = min(s.lineEnd(from: i), end)
            let close = s.find("'", from: i + 2, until: lineEnd).map { $0 + 1 } ?? lineEnd
            sink.add(.string, i..<close)
            return close
        }
        let width = UTF16.isLeadSurrogate(s[i + 1]) ? 2 : 1
        if s[i + 1 + width] == ASCII.apostrophe && !SourceText.isNewline(s[i + 1]) {
            sink.add(.string, i..<(i + 2 + width))
            return i + 2 + width
        }
        if SourceText.isIdentifierStart(s[i + 1]) {
            let wordEnd = s.identifierEnd(from: i + 1)
            sink.add(.type, i..<wordEnd)
            return wordEnd
        }
        return nil
    }

    // MARK: Numbers

    private func number(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        let c = s[i]
        let startsWithDot = c == ASCII.dot && SourceText.isDigit(s[i + 1]) && !SourceText.isIdentifierPart(s[i - 1])
            && s[i - 1] != ASCII.dot
        guard SourceText.isDigit(c) || startsWithDot else { return nil }
        let close = min(Self.numberEnd(s, from: i), end)
        sink.add(.number, i..<close)
        return close
    }

    /// Decimal, hex `0x`, binary `0b`, octal `0o`, underscores, fractions, exponents and type suffixes (`10f`, `3u8`).
    static func numberEnd(_ s: SourceText, from i: Int) -> Int {
        var j = i
        let prefix = SourceText.lowercased(s[i + 1])
        if s[i] == 0x30 && (prefix == 0x78 || prefix == 0x62 || prefix == 0x6F) {         // 0x 0b 0o
            j += 2
            while SourceText.isHexDigit(s[j]) || s[j] == 0x5F { j += 1 }
        } else {
            while SourceText.isDigit(s[j]) || s[j] == 0x5F { j += 1 }
            if s[j] == 0x2E && SourceText.isDigit(s[j + 1]) {
                j += 1
                while SourceText.isDigit(s[j]) || s[j] == 0x5F { j += 1 }
            }
            let e = SourceText.lowercased(s[j])
            if e == 0x65 && (SourceText.isDigit(s[j + 1]) || ((s[j + 1] == 0x2B || s[j + 1] == 0x2D) && SourceText.isDigit(s[j + 2]))) {
                j += 2
                while SourceText.isDigit(s[j]) { j += 1 }
            }
        }
        while SourceText.isLetter(s[j]) || (SourceText.isDigit(s[j]) && j > i) { j += 1 }         // suffixes: f, L, u8, i32
        return j
    }

    // MARK: @attributes, #directives, $variables, Ruby symbols

    private func prefixed(_ s: SourceText, at i: Int, end: Int, lineStart: Bool, sink: inout TokenSink) -> Int? {
        let c = s[i]
        if spec.rust && c == ASCII.hash && (s[i + 1] == ASCII.openBracket || (s[i + 1] == ASCII.bang && s[i + 2] == ASCII.openBracket)) {
            let lineEnd = min(s.lineEnd(from: i), end)
            let close = s.find("]", from: i, until: lineEnd).map { $0 + 1 } ?? lineEnd
            sink.add(.keyword, i..<close)
            return close
        }
        if c == ASCII.at && (spec.attributePrefix || spec.ruby) {
            let start = spec.ruby && s[i + 1] == ASCII.at ? i + 2 : i + 1
            guard SourceText.isIdentifierStart(s[start]) else { return nil }
            let wordEnd = min(s.identifierEnd(from: start), end)
            sink.add(spec.ruby ? .type : .keyword, i..<wordEnd)
            return wordEnd
        }
        if c == ASCII.hash, spec.directives == .anywhere || (spec.directives == .lineStart && lineStart),
           SourceText.isIdentifierStart(s[i + 1]) {
            let wordEnd = min(s.identifierEnd(from: i + 1), end)
            sink.add(.keyword, i..<wordEnd)
            let name = s.string((i + 1)..<wordEnd)
            if name == "include" || name == "import" {                       // #include <stdio.h>
                let j = s.skipSpaces(from: wordEnd, until: end)
                if s[j] == ASCII.less, let close = s.find(">", from: j, until: min(s.lineEnd(from: j), end)) {
                    sink.add(.string, j..<(close + 1))
                    return close + 1
                }
            }
            return wordEnd
        }
        if c == ASCII.dollar && spec.dollarVariables { return shellVariable(s, at: i, end: end, sink: &sink) }
        if spec.ruby && c == ASCII.colon && s[i - 1] != ASCII.colon && !SourceText.isIdentifierPart(s[i - 1])
            && SourceText.isIdentifierStart(s[i + 1]) {
            let wordEnd = min(s.identifierEnd(from: i + 1), end)
            sink.add(.string, i..<wordEnd)
            return wordEnd
        }
        return nil
    }

    private func shellVariable(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        let next = s[i + 1]
        let close: Int
        if next == ASCII.openBrace {
            let lineEnd = min(s.lineEnd(from: i), end)
            close = s.find("}", from: i, until: lineEnd).map { $0 + 1 } ?? lineEnd
        } else if SourceText.isIdentifierStart(next) {
            close = min(s.identifierEnd(from: i + 1), end)
        } else if SourceText.isDigit(next) || [0x23, 0x3F, 0x40, 0x2A, 0x24, 0x21, 0x2D].contains(next) {   // # ? @ * $ ! -
            close = min(i + 2, end)
        } else {
            return nil
        }
        sink.add(.type, i..<close)
        return close
    }

    // MARK: Identifiers

    private func identifier(_ s: SourceText, at i: Int, end: Int, sink: inout TokenSink) -> Int? {
        guard SourceText.isIdentifierStart(s[i]) else { return nil }
        var wordEnd = min(s.identifierEnd(from: i), end)
        if spec.ruby && (s[wordEnd] == ASCII.question || s[wordEnd] == ASCII.bang) && wordEnd < end { wordEnd += 1 }
        let word = s.string(i..<wordEnd)
        if spec.stringPrefixes.contains(word), let close = delimited(s, at: wordEnd, end: end) {
            sink.add(.string, i..<close)                                     // r"…", f'…', b"…"
            return close
        }
        if let kind = classify(word, s, at: i, wordEnd: wordEnd) {
            if kind == .function && spec.rust && s[wordEnd] == ASCII.bang {
                sink.add(.function, i..<(wordEnd + 1))                       // println!
                return wordEnd + 1
            }
            sink.add(kind, i..<wordEnd)
        }
        return wordEnd
    }

    private func classify(_ word: String, _ s: SourceText, at i: Int, wordEnd: Int) -> SyntaxKind? {
        if spec.keywords.contains(spec.caseInsensitiveKeywords ? word.lowercased() : word) { return .keyword }
        if spec.types.contains(word) { return .type }
        if spec.capitalizedTypes && SourceText.isUpper(s[i]) { return .type }
        if spec.rust && s[wordEnd] == ASCII.bang
            && [ASCII.openParen, ASCII.openBracket, ASCII.openBrace].contains(s[wordEnd + 1]) { return .function }
        if spec.detectsFunctions && s[s.skipSpaces(from: wordEnd)] == ASCII.openParen { return .function }
        return nil
    }
}
