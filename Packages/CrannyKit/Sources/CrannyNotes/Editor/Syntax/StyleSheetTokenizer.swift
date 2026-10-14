// CrannyNotes/Editor/Syntax/StyleSheetTokenizer.swift — CSS (and the common subset of SCSS/Less): selectors
// (function colour), properties (type), at-rules and `!important` (keyword), numbers with units and hex
// colours (number), `url(…)`/`rgb(…)` (function), strings and comments.
import Foundation

nonisolated struct StyleSheetTokenizer {
    private enum ASCII {
        static let openBrace: UInt16 = 0x7B, closeBrace: UInt16 = 0x7D, at: UInt16 = 0x40, dot: UInt16 = 0x2E
        static let hash: UInt16 = 0x23, colon: UInt16 = 0x3A, dash: UInt16 = 0x2D, openParen: UInt16 = 0x28
        static let bang: UInt16 = 0x21, quote: UInt16 = 0x22, apostrophe: UInt16 = 0x27, percent: UInt16 = 0x25
        static let semicolon: UInt16 = 0x3B
    }

    private static let quoted = [LanguageSpec.Delimited(open: "\"", close: "\""), LanguageSpec.Delimited(open: "'", close: "'")]

    func tokenize(_ s: SourceText, in range: Range<Int>, into sink: inout TokenSink) {
        var i = range.lowerBound
        let end = min(range.upperBound, s.count)
        var depth = 0
        var inValue = false                                                      // after `prop:` until `;` or `}`
        while i < end {
            let c = s[i]
            if s.matches("/*", at: i) {
                let close = s.find("*/", from: i + 2, until: end).map { $0 + 2 } ?? end
                sink.add(.comment, i..<close)
                i = close
            } else if c == ASCII.quote || c == ASCII.apostrophe {
                let rule = c == ASCII.quote ? Self.quoted[0] : Self.quoted[1]
                let close = min(CodeTokenizer.scan(s, rule: rule, from: i + 1, end: end), end)
                sink.add(.string, i..<close)
                i = close
            } else if c == ASCII.openBrace {
                depth += 1; inValue = false; i += 1
            } else if c == ASCII.closeBrace {
                depth = max(depth - 1, 0); inValue = false; i += 1
            } else if c == ASCII.semicolon {
                inValue = false; i += 1
            } else if c == ASCII.at && isIdentStart(s[i + 1]) {
                let close = identEnd(s, from: i + 1, end: end)
                sink.add(.keyword, i..<close)
                i = close
            } else if c == ASCII.bang && s.matches("!important", at: i, caseInsensitive: true) {
                sink.add(.keyword, i..<(i + 10))
                i += 10
            } else if depth == 0 || !inValue && opensBlock(s, at: i, end: end) {
                i = selector(s, at: i, end: end, into: &sink)                    // nested rule (SCSS, @media)
            } else {
                i = declaration(s, at: i, end: end, inValue: &inValue, into: &sink)
            }
        }
    }

    // MARK: Selectors (outside blocks, and nested SCSS rules inside them)

    private func selector(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int {
        let c = s[i]
        if (c == ASCII.dot || c == ASCII.hash || c == ASCII.colon) && (isIdentStart(s[i + 1]) || s[i + 1] == ASCII.colon) {
            let start = s[i + 1] == ASCII.colon ? i + 2 : i + 1                 // ::before
            let close = identEnd(s, from: start, end: end)
            sink.add(.function, i..<close)
            return close
        }
        if isIdentStart(c) {
            let close = identEnd(s, from: i, end: end)
            sink.add(.function, i..<close)
            return close
        }
        return i + 1
    }

    /// Inside a block, a nested selector (`p:hover {`, `.a {`) reaches `{` before any `;` or `}`; a declaration
    /// (`color: red;`) does not. Looks a short way ahead only.
    private func opensBlock(_ s: SourceText, at i: Int, end: Int) -> Bool {
        var j = i
        let limit = min(end, i + 256)
        while j < limit {
            switch s[j] {
            case ASCII.openBrace: return true
            case ASCII.semicolon, ASCII.closeBrace: return false
            default: j += 1
            }
        }
        return false
    }

    // MARK: Declarations

    private func declaration(_ s: SourceText, at i: Int, end: Int, inValue: inout Bool, into sink: inout TokenSink) -> Int {
        let c = s[i]
        if !inValue && (isIdentStart(c) || (c == ASCII.dash && (isIdentStart(s[i + 1]) || s[i + 1] == ASCII.dash))) {
            let close = identEnd(s, from: i, end: end)
            if s[s.skipSpaces(from: close, until: end)] == ASCII.colon {
                sink.add(.type, i..<close)                                       // property (incl. --custom)
                inValue = true
            }
            return close
        }
        if c == ASCII.colon { inValue = true; return i + 1 }
        if SourceText.isDigit(c) || ((c == ASCII.dot || c == ASCII.dash) && SourceText.isDigit(s[i + 1]) && !isIdentPart(s[i - 1])) {
            var j = i + 1
            while j < end && (SourceText.isDigit(s[j]) || s[j] == ASCII.dot) { j += 1 }
            while j < end && (SourceText.isLetter(s[j]) || s[j] == ASCII.percent) { j += 1 }        // px, em, %, deg
            sink.add(.number, i..<j)
            return j
        }
        if c == ASCII.hash && SourceText.isHexDigit(s[i + 1]) {
            var j = i + 1
            while j < end && SourceText.isHexDigit(s[j]) { j += 1 }
            sink.add(.number, i..<j)                                             // #fff, #1e2026
            return j
        }
        if isIdentStart(c) || c == ASCII.dash {
            let close = identEnd(s, from: i, end: end)
            if s[close] == ASCII.openParen { sink.add(.function, i..<close) }     // rgb( url( var(
            return close
        }
        return i + 1
    }

    private func isIdentStart(_ c: UInt16) -> Bool { SourceText.isIdentifierStart(c) }
    private func isIdentPart(_ c: UInt16) -> Bool { SourceText.isIdentifierPart(c) || c == ASCII.dash }
    private func identEnd(_ s: SourceText, from i: Int, end: Int) -> Int {
        var j = i
        while j < end && isIdentPart(s[j]) { j += 1 }
        return j
    }
}
