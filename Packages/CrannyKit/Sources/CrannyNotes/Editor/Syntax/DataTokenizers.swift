// CrannyNotes/Editor/Syntax/DataTokenizers.swift — JSON (keys as type, values as string/number/keyword,
// JSONC comments) and YAML (keys, scalars, comments, anchors, block scalars, document markers).
import Foundation

nonisolated struct JSONTokenizer {
    private static let quoted = LanguageSpec.Delimited(open: "\"", close: "\"")

    func tokenize(_ s: SourceText, in range: Range<Int>, into sink: inout TokenSink) {
        var i = range.lowerBound
        let end = min(range.upperBound, s.count)
        while i < end {
            let c = s[i]
            if c == 0x22 {                                                       // "
                let close = min(CodeTokenizer.scan(s, rule: Self.quoted, from: i + 1, end: end), end)
                var after = close
                while after < end && SourceText.isWhitespace(s[after]) { after += 1 }
                sink.add(s[after] == 0x3A ? .type : .string, i..<close)          // "key": vs "value"
                i = close
            } else if SourceText.isDigit(c) || (c == 0x2D && SourceText.isDigit(s[i + 1])) {
                var j = i + 1
                while j < end && (SourceText.isDigit(s[j]) || [0x2E, 0x65, 0x45, 0x2B, 0x2D].contains(s[j])) { j += 1 }
                sink.add(.number, i..<j)
                i = j
            } else if SourceText.isLetter(c) {
                let close = min(s.identifierEnd(from: i), end)
                if ["true", "false", "null"].contains(s.string(i..<close)) { sink.add(.keyword, i..<close) }
                i = close
            } else if s.matches("//", at: i) {
                let close = min(s.lineEnd(from: i), end)
                sink.add(.comment, i..<close)
                i = close
            } else if s.matches("/*", at: i) {
                let close = s.find("*/", from: i + 2, until: end).map { $0 + 2 } ?? end
                sink.add(.comment, i..<close)
                i = close
            } else {
                i += 1
            }
        }
    }
}

nonisolated struct YAMLTokenizer {
    private static let keywords: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~"]
    private static let rules = [LanguageSpec.Delimited(open: "\"", close: "\""),
                                LanguageSpec.Delimited(open: "'", close: "'", escapes: false)]

    func tokenize(_ s: SourceText, in range: Range<Int>, into sink: inout TokenSink) {
        let end = min(range.upperBound, s.count)
        var lineStart = range.lowerBound
        var blockScalarIndent: Int?                                              // inside `key: |` text
        while lineStart < end {
            let lineEnd = min(s.lineEnd(from: lineStart), end)
            let next = lineEnd >= end ? end : lineEnd + (s[lineEnd] == 0x0D && s[lineEnd + 1] == 0x0A ? 2 : 1)
            let indentEnd = s.skipSpaces(from: lineStart, until: lineEnd)
            let indent = indentEnd - lineStart
            if let scalarIndent = blockScalarIndent, indentEnd == lineEnd || indent > scalarIndent {
                sink.add(.string, indentEnd..<lineEnd)
            } else {
                blockScalarIndent = nil
                if line(s, indentEnd..<lineEnd, lineStart: lineStart, into: &sink) { blockScalarIndent = indent }
            }
            lineStart = next
        }
    }

    /// Returns true when the line opens a block scalar (`key: |` or `key: >-`).
    private func line(_ s: SourceText, _ line: Range<Int>, lineStart: Int, into sink: inout TokenSink) -> Bool {
        var i = line.lowerBound
        let end = line.upperBound
        guard i < end else { return false }
        if i == lineStart && (s.matches("---", at: i) || s.matches("...", at: i)) && s.skipSpaces(from: i + 3, until: end) == end {
            sink.add(.marker, i..<end)
            return false
        }
        while s[i] == 0x2D && (i + 1 == end || SourceText.isSpace(s[i + 1])) {     // "- " sequence entries
            sink.add(.marker, i..<(i + 1))
            i = s.skipSpaces(from: i + 1, until: end)
        }
        if s[i] == 0x23 { sink.add(.comment, i..<end); return false }
        if let colon = keyEnd(s, from: i, end: end) {
            sink.add(.type, i..<colon)
            i = colon + 1
        }
        return value(s, i..<end, into: &sink)
    }

    /// The index of the `:` that ends a mapping key starting at `i`, or nil.
    private func keyEnd(_ s: SourceText, from i: Int, end: Int) -> Int? {
        var j = i
        if s[j] == 0x22 || s[j] == 0x27 {
            j = CodeTokenizer.scan(s, rule: s[j] == 0x22 ? Self.rules[0] : Self.rules[1], from: j + 1, end: end)
            j = s.skipSpaces(from: j, until: end)
            return s[j] == 0x3A && (j + 1 == end || SourceText.isSpace(s[j + 1])) ? j : nil
        }
        while j < end {
            let c = s[j]
            if c == 0x3A && (j + 1 == end || SourceText.isSpace(s[j + 1])) { return j > i ? j : nil }
            if c == 0x23 && SourceText.isSpace(s[j - 1]) { return nil }
            if [0x7B, 0x5B, 0x22, 0x27].contains(c) && j == i { return nil }
            j += 1
        }
        return nil
    }

    private func value(_ s: SourceText, _ range: Range<Int>, into sink: inout TokenSink) -> Bool {
        var i = s.skipSpaces(from: range.lowerBound, until: range.upperBound)
        let end = range.upperBound
        while i < end {
            let c = s[i]
            if c == 0x23 && (i == range.lowerBound || SourceText.isSpace(s[i - 1])) {
                sink.add(.comment, i..<end)
                return false
            }
            if c == 0x22 || c == 0x27 {
                let close = min(CodeTokenizer.scan(s, rule: c == 0x22 ? Self.rules[0] : Self.rules[1], from: i + 1, end: end), end)
                sink.add(.string, i..<close)
                i = close
                continue
            }
            if (c == 0x26 || c == 0x2A) && SourceText.isIdentifierStart(s[i + 1]) {     // &anchor *alias
                let close = min(s.identifierEnd(from: i + 1), end)
                sink.add(.function, i..<close)
                i = close
                continue
            }
            if c == 0x21 {                                                       // !tag
                var j = i + 1
                while j < end && !SourceText.isWhitespace(s[j]) { j += 1 }
                sink.add(.keyword, i..<j)
                i = j
                continue
            }
            if (c == 0x7C || c == 0x3E) && s.skipSpaces(from: blockIndicatorEnd(s, from: i + 1, end: end), until: end) == end {
                sink.add(.marker, i..<end)                                       // | |- >+
                return true
            }
            return scalar(s, i..<end, into: &sink)
        }
        return false
    }

    private func blockIndicatorEnd(_ s: SourceText, from i: Int, end: Int) -> Int {
        var j = i
        while j < end && (s[j] == 0x2D || s[j] == 0x2B || SourceText.isDigit(s[j])) { j += 1 }
        return j
    }

    /// A plain scalar up to a ` #` comment: number, boolean/null keyword or plain text.
    private func scalar(_ s: SourceText, _ range: Range<Int>, into sink: inout TokenSink) -> Bool {
        var j = range.lowerBound
        while j < range.upperBound && !(s[j] == 0x23 && SourceText.isSpace(s[j - 1])) { j += 1 }
        var valueEnd = j
        while valueEnd > range.lowerBound && SourceText.isSpace(s[valueEnd - 1]) { valueEnd -= 1 }
        let text = s.string(range.lowerBound..<valueEnd)
        if Self.keywords.contains(text.lowercased()) {
            sink.add(.keyword, range.lowerBound..<valueEnd)
        } else if let first = text.utf16.first, SourceText.isDigit(first) || [0x2D, 0x2B, 0x2E].contains(first),
                  Double(text.replacingOccurrences(of: "_", with: "")) != nil || text.hasPrefix("0x") {
            sink.add(.number, range.lowerBound..<valueEnd)
        }
        if j < range.upperBound { sink.add(.comment, j..<range.upperBound) }
        return false
    }
}
