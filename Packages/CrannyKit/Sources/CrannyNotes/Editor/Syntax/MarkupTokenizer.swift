// CrannyNotes/Editor/Syntax/MarkupTokenizer.swift — HTML and XML: tags (keyword), attribute names (type),
// attribute values (string), comments, `<!DOCTYPE>`/`<?xml?>` (keyword), entities (number). The bodies of
// `<script>` and `<style>` are handed to the JavaScript and CSS tokenizers. A tag or comment is consumed in one
// step, so a line start between them carries nothing; inside a body it carries the body's kind
// (`LexLevel.embedded`) and that tokenizer's state, and a resumed pass looks for the closing tag from there.
import Foundation

nonisolated struct MarkupTokenizer {
    var depth = 0

    private enum ASCII {
        static let less: UInt16 = 0x3C, greater: UInt16 = 0x3E, slash: UInt16 = 0x2F, bang: UInt16 = 0x21
        static let question: UInt16 = 0x3F, equals: UInt16 = 0x3D, quote: UInt16 = 0x22, apostrophe: UInt16 = 0x27
        static let ampersand: UInt16 = 0x26, semicolon: UInt16 = 0x3B, hash: UInt16 = 0x23
    }

    /// `state`: where a resumed pass starts (`range.lowerBound` is then a line start between tags or in a body).
    func tokenize(_ s: SourceText, in range: Range<Int>, resuming state: LexState? = nil, into sink: inout TokenSink) {
        var i = range.lowerBound
        let end = min(range.upperBound, s.count)
        if let state, case .embedded(let script) = state.level {
            i = body(script: script, s, from: i, end: end, resuming: state.nested, into: &sink)
            if sink.isStopped { return }
        }
        while i < end {
            sink.checkpoint(s, at: i, before: end, .none)
            if sink.isStopped { return }
            if s.matches("<!--", at: i) {
                i = delimited(.comment, s, from: i, open: 4, close: "-->", end: end, into: &sink)
            } else if s.matches("<![CDATA[", at: i) {
                i = delimited(.string, s, from: i, open: 9, close: "]]>", end: end, into: &sink)
            } else if s.matches("<?", at: i) {
                i = delimited(.keyword, s, from: i, open: 2, close: "?>", end: end, into: &sink)
            } else if s[i] == ASCII.less && s[i + 1] == ASCII.bang {
                i = delimited(.keyword, s, from: i, open: 2, close: ">", end: end, into: &sink)
            } else if s[i] == ASCII.less && (isNameStart(s[i + 1]) || (s[i + 1] == ASCII.slash && isNameStart(s[i + 2]))) {
                i = tag(s, at: i, end: end, into: &sink)
                if sink.isStopped { return }
            } else if s[i] == ASCII.ampersand, let close = entityEnd(s, at: i, end: end) {
                sink.add(.number, i..<close)
                i = close
            } else {
                i += 1
            }
        }
    }

    private func delimited(_ kind: SyntaxKind, _ s: SourceText, from i: Int, open: Int, close: String, end: Int,
                           into sink: inout TokenSink) -> Int {
        let closeEnd = s.find(close, from: i + open, until: end).map { $0 + close.utf16.count } ?? end
        sink.add(kind, i..<closeEnd)
        return closeEnd
    }

    /// `<name attr="v" flag>` or `</name>`; returns the index after `>`.
    private func tag(_ s: SourceText, at i: Int, end: Int, into sink: inout TokenSink) -> Int {
        let closing = s[i + 1] == ASCII.slash
        let nameStart = i + (closing ? 2 : 1)
        var j = nameStart
        while j < end && isNamePart(s[j]) { j += 1 }
        sink.add(.keyword, nameStart..<j)
        let name = s.string(nameStart..<j).lowercased()
        var selfClosing = false
        while j < end {
            let c = s[j]
            if c == ASCII.greater { j += 1; break }
            if c == ASCII.slash && s[j + 1] == ASCII.greater { selfClosing = true; j += 2; break }
            if c == ASCII.less { break }                                          // malformed: next tag starts
            if SourceText.isWhitespace(c) || c == ASCII.slash { j += 1; continue }
            if c == ASCII.equals {
                j = s.skipSpaces(from: j + 1, until: end)
                j = attributeValue(s, at: j, end: end, into: &sink)
                continue
            }
            var nameEnd = j
            while nameEnd < end && !SourceText.isWhitespace(s[nameEnd])
                    && ![ASCII.equals, ASCII.greater, ASCII.slash, ASCII.less].contains(s[nameEnd]) { nameEnd += 1 }
            sink.add(.type, j..<nameEnd)
            j = max(nameEnd, j + 1)
        }
        if !closing && !selfClosing && (name == "script" || name == "style") {
            guard depth < 2 else {
                let bodyEnd = findClosingTag(name, s, from: j, end: end)
                readClosingTag(name, at: bodyEnd, s, end: end, into: &sink)
                return bodyEnd
            }
            return body(script: name == "script", s, from: j, end: end, resuming: nil, into: &sink)
        }
        return j
    }

    /// A `<script>` or `<style>` body from `start` (just after its tag, or a line start inside it where its tokenizer
    /// was in `state`) to its closing tag: returns where that tag starts.
    private func body(script: Bool, _ s: SourceText, from start: Int, end: Int, resuming state: LexState?,
                      into sink: inout TokenSink) -> Int {
        let name = script ? "script" : "style"
        let bodyEnd = findClosingTag(name, s, from: start, end: end)
        sink.enter(.embedded(script: script))
        SyntaxHighlighter.tokenize(s, in: start..<bodyEnd, language: script ? .javascript : .css, depth: depth + 1,
                                   resuming: state, into: &sink)
        sink.leave()
        readClosingTag(name, at: bodyEnd, s, end: end, into: &sink)
        return bodyEnd
    }

    /// The body ends at `bodyEnd` because `</name` starts there. When that is a line start, its state depends on the
    /// tag's characters after it, so the look counts in its reach. Reported after the body's tokens: the line starts
    /// inside the body depend only on the text before them (a tag never spans a line end) and keep their reach.
    private func readClosingTag(_ name: String, at bodyEnd: Int, _ s: SourceText, end: Int, into sink: inout TokenSink) {
        guard bodyEnd < end else { return }
        sink.read(upTo: bodyEnd + 1 + name.utf16.count, end: end, in: s)
    }

    private func attributeValue(_ s: SourceText, at j: Int, end: Int, into sink: inout TokenSink) -> Int {
        let c = s[j]
        if c == ASCII.quote || c == ASCII.apostrophe {
            let close = s.find(c == ASCII.quote ? "\"" : "'", from: j + 1, until: end).map { $0 + 1 } ?? end
            sink.add(.string, j..<close)
            return close
        }
        var k = j
        while k < end && !SourceText.isWhitespace(s[k]) && s[k] != ASCII.greater { k += 1 }
        sink.add(.string, j..<k)
        return max(k, j + 1)
    }

    private func findClosingTag(_ name: String, _ s: SourceText, from start: Int, end: Int) -> Int {
        var j = start
        while let candidate = s.find("</", from: j, until: end) {
            if s.matches(name, at: candidate + 2, caseInsensitive: true) { return candidate }
            j = candidate + 2
        }
        return end
    }

    /// `&amp;`, `&#38;`, `&#x26;` (at most 12 characters).
    private func entityEnd(_ s: SourceText, at i: Int, end: Int) -> Int? {
        var j = i + 1
        if s[j] == ASCII.hash { j += 1 }
        let bodyStart = j
        while j < end && j - i <= 12 && (SourceText.isLetter(s[j]) || SourceText.isDigit(s[j])) { j += 1 }
        return j > bodyStart && s[j] == ASCII.semicolon ? j + 1 : nil
    }

    private func isNameStart(_ c: UInt16) -> Bool { SourceText.isLetter(c) || c == 0x5F || c == 0x3A }
    private func isNamePart(_ c: UInt16) -> Bool { isNameStart(c) || SourceText.isDigit(c) || c == 0x2D || c == 0x2E }
}
