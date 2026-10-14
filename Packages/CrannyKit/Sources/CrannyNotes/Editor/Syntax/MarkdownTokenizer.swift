// CrannyNotes/Editor/Syntax/MarkdownTokenizer.swift — Markdown for code mode (DESIGN.md §7.5): headings, quotes,
// lists, rules, fences (with their own language), inline code, links, emphasis. Punctuation is a dimmed
// `.marker` so the prose stays the brightest thing on the card. Line-based; a fence is the only multi-line state.
import Foundation

nonisolated struct MarkdownTokenizer {
    /// Fences nest their own tokenizer; a Markdown fence inside Markdown goes one level deep at most.
    var depth = 0

    private enum ASCII {
        static let hash: UInt16 = 0x23, greater: UInt16 = 0x3E, dash: UInt16 = 0x2D, star: UInt16 = 0x2A
        static let plus: UInt16 = 0x2B, underscore: UInt16 = 0x5F, backtick: UInt16 = 0x60, tilde: UInt16 = 0x7E
        static let openBracket: UInt16 = 0x5B, closeBracket: UInt16 = 0x5D, openParen: UInt16 = 0x28
        static let closeParen: UInt16 = 0x29, bang: UInt16 = 0x21, less: UInt16 = 0x3C, dot: UInt16 = 0x2E
        static let equals: UInt16 = 0x3D, space: UInt16 = 0x20, cr: UInt16 = 0x0D, lf: UInt16 = 0x0A
    }

    private struct Fence {
        var character: UInt16
        var length: Int
        var language: CodeLanguage?
        var bodyStart: Int
    }

    func tokenize(_ s: SourceText, in range: Range<Int>, into sink: inout TokenSink) {
        let end = min(range.upperBound, s.count)
        var lineStart = range.lowerBound
        var fence: Fence?
        while lineStart < end {
            let lineEnd = min(s.lineEnd(from: lineStart), end)
            let next = lineEnd >= end ? end : lineEnd + (s[lineEnd] == ASCII.cr && s[lineEnd + 1] == ASCII.lf ? 2 : 1)
            let indent = s.skipSpaces(from: lineStart, until: lineEnd)
            let shallow = indent - lineStart <= 3
            if let open = fence {
                if shallow && closesFence(open, s, at: indent, lineEnd: lineEnd) {
                    fenceBody(open, s, open.bodyStart..<lineStart, into: &sink)
                    sink.add(.marker, indent..<lineEnd)
                    fence = nil
                }
            } else if shallow, let opened = openFence(s, at: indent, lineEnd: lineEnd, next: next, into: &sink) {
                fence = opened
            } else {
                block(s, indent..<lineEnd, into: &sink)
            }
            lineStart = next
        }
        if let open = fence { fenceBody(open, s, open.bodyStart..<end, into: &sink) }   // unclosed fence: to the end
    }

    // MARK: Fences

    private func openFence(_ s: SourceText, at i: Int, lineEnd: Int, next: Int, into sink: inout TokenSink) -> Fence? {
        let c = s[i]
        guard c == ASCII.backtick || c == ASCII.tilde else { return nil }
        var j = i
        while j < lineEnd && s[j] == c { j += 1 }
        guard j - i >= 3 else { return nil }
        let infoStart = s.skipSpaces(from: j, until: lineEnd)
        var infoEnd = infoStart
        while infoEnd < lineEnd && !SourceText.isWhitespace(s[infoEnd]) && s[infoEnd] != 0x7B { infoEnd += 1 }   // ```swift {…}
        if c == ASCII.backtick && s.find("`", from: j, until: lineEnd) != nil { return nil }   // ``` `x` is inline code
        sink.add(.marker, i..<j)
        sink.add(.keyword, infoStart..<infoEnd)
        sink.add(.marker, infoEnd..<lineEnd)
        return Fence(character: c, length: j - i, language: CodeLanguage(alias: s.string(infoStart..<infoEnd)), bodyStart: next)
    }

    private func closesFence(_ fence: Fence, _ s: SourceText, at i: Int, lineEnd: Int) -> Bool {
        var j = i
        while j < lineEnd && s[j] == fence.character { j += 1 }
        return j - i >= fence.length && s.skipSpaces(from: j, until: lineEnd) == lineEnd
    }

    private func fenceBody(_ fence: Fence, _ s: SourceText, _ body: Range<Int>, into sink: inout TokenSink) {
        guard !body.isEmpty else { return }
        if fence.language == .markdown && depth > 0 { return }
        SyntaxHighlighter.tokenize(s, in: body, language: fence.language, depth: depth + 1, into: &sink)
    }

    // MARK: Block-level prefixes

    private func block(_ s: SourceText, _ line: Range<Int>, into sink: inout TokenSink) {
        guard !line.isEmpty else { return }
        var i = line.lowerBound
        let end = line.upperBound
        if s[i] == ASCII.hash {
            var hashes = i
            while hashes < end && s[hashes] == ASCII.hash { hashes += 1 }
            if hashes - i <= 6 && (hashes == end || SourceText.isSpace(s[hashes])) {
                sink.add(.marker, i..<hashes)
                sink.add(.heading, s.skipSpaces(from: hashes, until: end)..<end)
                return
            }
        }
        if isRule(s, line) { sink.add(.marker, line); return }
        while i < end && s[i] == ASCII.greater {                                 // > quotes, nested
            sink.add(.marker, i..<(i + 1))
            i = s.skipSpaces(from: i + 1, until: end)
        }
        if let markerEnd = listMarkerEnd(s, at: i, end: end) {
            sink.add(.marker, i..<markerEnd)
            i = s.skipSpaces(from: markerEnd, until: end)
            if s[i] == ASCII.openBracket && s[i + 2] == ASCII.closeBracket && [ASCII.space, 0x78, 0x58].contains(s[i + 1]) {
                sink.add(.marker, i..<(i + 3))                                       // [ ] / [x]
                i += 3
            }
        }
        inline(s, i..<end, into: &sink)
    }

    /// `---`, `***`, `___` (spaces allowed) and setext underlines `===`.
    private func isRule(_ s: SourceText, _ line: Range<Int>) -> Bool {
        let first = s[line.lowerBound]
        guard [ASCII.dash, ASCII.star, ASCII.underscore, ASCII.equals].contains(first) else { return false }
        var count = 0
        for j in line {
            if s[j] == first { count += 1 } else if !SourceText.isSpace(s[j]) { return false }
        }
        return count >= 3
    }

    private func listMarkerEnd(_ s: SourceText, at i: Int, end: Int) -> Int? {
        let c = s[i]
        if (c == ASCII.dash || c == ASCII.star || c == ASCII.plus) && (i + 1 == end || SourceText.isSpace(s[i + 1])) { return i + 1 }
        var j = i
        while j < end && j - i < 9 && SourceText.isDigit(s[j]) { j += 1 }
        if j > i && (s[j] == ASCII.dot || s[j] == ASCII.closeParen) && (j + 1 == end || SourceText.isSpace(s[j + 1])) { return j + 1 }
        return nil
    }

    // MARK: Inline

    private func inline(_ s: SourceText, _ range: Range<Int>, into sink: inout TokenSink) {
        var i = range.lowerBound
        let end = range.upperBound
        while i < end {
            let c = s[i]
            if c == SourceText.backslash { i += 2; continue }
            if let next = codeSpan(s, at: i, end: end, into: &sink)
                ?? link(s, at: i, end: end, into: &sink)
                ?? autolink(s, at: i, end: end, into: &sink)
                ?? emphasis(s, at: i, end: end, into: &sink) {
                i = max(next, i + 1)
            } else {
                i += 1
            }
        }
    }

    private func codeSpan(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int? {
        guard s[i] == ASCII.backtick else { return nil }
        var run = i
        while run < end && s[run] == ASCII.backtick { run += 1 }
        let width = run - i
        var j = run
        while j < end {
            if s[j] == ASCII.backtick {
                var close = j
                while close < end && s[close] == ASCII.backtick { close += 1 }
                if close - j == width {
                    sink.add(.code, i..<close)
                    return close
                }
                j = close
            } else {
                j += 1
            }
        }
        return run                                                                // unmatched: plain backticks
    }

    /// `[text](url)` and `![alt](url)`: the text is a link, the brackets and the URL are markers.
    private func link(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int? {
        let image = s[i] == ASCII.bang && s[i + 1] == ASCII.openBracket
        guard s[i] == ASCII.openBracket || image else { return nil }
        let open = image ? i + 1 : i
        guard let close = s.find("]", from: open + 1, until: end), s[close + 1] == ASCII.openParen,
              let urlEnd = s.find(")", from: close + 2, until: end) else { return nil }
        sink.add(.marker, i..<(open + 1))
        sink.add(.link, (open + 1)..<close)
        sink.add(.marker, close..<(urlEnd + 1))
        return urlEnd + 1
    }

    /// `<https://…>` and bare `https://…` URLs.
    private func autolink(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int? {
        if s[i] == ASCII.less, s.matches("http", at: i + 1, caseInsensitive: true),
           let close = s.find(">", from: i + 1, until: end) {
            sink.add(.link, i..<(close + 1))
            return close + 1
        }
        guard s.matches("https://", at: i, caseInsensitive: true) || s.matches("http://", at: i, caseInsensitive: true),
              !SourceText.isIdentifierPart(s[i - 1]) else { return nil }
        var j = i
        while j < end && !SourceText.isWhitespace(s[j]) && s[j] != ASCII.less { j += 1 }
        while j > i && [ASCII.dot, 0x2C, 0x3B, 0x3A, ASCII.bang, 0x3F, ASCII.closeParen].contains(s[j - 1]) { j -= 1 }
        sink.add(.link, i..<j)
        return j
    }

    /// `*em*`, `_em_`, `**strong**`, `__strong__`, `***both***` on one line. Openers need a non-space after
    /// them, closers a non-space before; `_` only counts at word boundaries (snake_case stays plain).
    private func emphasis(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int? {
        let c = s[i]
        guard c == ASCII.star || c == ASCII.underscore else { return nil }
        if c == ASCII.underscore && SourceText.isIdentifierPart(s[i - 1]) { return nil }
        var run = i
        while run < end && s[run] == c { run += 1 }
        let width = min(run - i, 3)
        guard run < end, !SourceText.isWhitespace(s[run]) else { return run }
        var j = run
        while j < end {
            if s[j] == c && !SourceText.isWhitespace(s[j - 1]) {
                var close = j
                while close < end && s[close] == c { close += 1 }
                let closeOK = c == ASCII.star || !SourceText.isIdentifierPart(s[close])
                if close - j == width && closeOK {
                    sink.add(.marker, i..<(i + width))
                    sink.add(width >= 2 ? .strong : .emphasis, (i + width)..<j)
                    sink.add(.marker, j..<close)
                    return close
                }
                j = close
            } else {
                j += 1
            }
        }
        return run
    }
}
