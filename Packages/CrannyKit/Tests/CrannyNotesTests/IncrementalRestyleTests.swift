// `SyntaxHighlighter.changedRange`: restyling only the reported range after an edit must give exactly the
// colours of a full re-highlight, for every language and thousands of random edits (inserts, deletes, replaces).
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Incremental restyling") struct IncrementalRestyleTests {
    /// Per-UTF-16-unit kind, as the text storage would hold it.
    private func styles(_ tokens: [SyntaxToken], length: Int) -> [SyntaxKind?] {
        var result = [SyntaxKind?](repeating: nil, count: length)
        for token in tokens { for i in token.range.location..<NSMaxRange(token.range) { result[i] = token.kind } }
        return result
    }

    @Test(arguments: languageSamples.indices)
    func restylingTheChangedRangeMatchesAFullPass(_ index: Int) {
        let (language, sample) = languageSamples[index]
        var generator = SeededGenerator(seed: 0xC0FFEE + UInt64(index))
        let pieces = ["a", " ", "\n", "\"", "'", "`", "/", "*", "#", "<", ">", "{", "}", "-", "1", "//", "/*", "*/", "```",
                      "\"\"\"", "<!--", "-->", "x = \"y\"", "# h\n", ":"]
        var text = sample as NSString
        var tokens = SyntaxHighlighter.tokens(in: text as String, language: language)
        for step in 0..<150 {
            let length = text.length
            let location = Int.random(in: 0...length, using: &generator)
            let removed = Int.random(in: 0...3, using: &generator) == 0 ? min(Int.random(in: 0...6, using: &generator), length - location) : 0
            let inserted = Int.random(in: 0...4, using: &generator) == 0 ? "" : pieces[Int.random(in: 0..<pieces.count, using: &generator)]
            guard removed > 0 || !inserted.isEmpty else { continue }
            // Keep surrogate pairs whole (the samples are ASCII apart from a few letters).
            let replaced = NSRange(location: location, length: removed)
            let next = text.replacingCharacters(in: replaced, with: inserted) as NSString
            let insertedLength = (inserted as NSString).length
            let fresh = SyntaxHighlighter.tokens(in: next as String, language: language)
            let span = SyntaxHighlighter.changedRange(old: tokens, new: fresh,
                                                      edited: NSRange(location: location, length: insertedLength),
                                                      delta: insertedLength - removed, length: next.length)
            // What the storage holds after the edit: old styles around the edit, garbage in it.
            let before = styles(tokens, length: length)
            var storage = Array(before[..<location]) + [SyntaxKind?](repeating: .heading, count: insertedLength)
                + Array(before[(location + removed)...])
            let expected = styles(fresh, length: next.length)
            for i in span.location..<NSMaxRange(span) { storage[i] = expected[i] }
            #expect(storage == expected, "language \(language?.rawValue ?? "generic"), step \(step), span \(span)")
            if storage != expected { return }
            text = next
            tokens = fresh
        }
    }

    @Test func typingInsideAWordRestylesOnlyThatWord() {
        let text = "let alpha = 1\nlet beta = 2\nlet gamma = 3\n"
        let old = SyntaxHighlighter.tokens(in: text, language: .swift)
        let edited = (text as NSString).replacingCharacters(in: NSRange(location: 19, length: 0), with: "x")   // betxa
        let new = SyntaxHighlighter.tokens(in: edited, language: .swift)
        let span = SyntaxHighlighter.changedRange(old: old, new: new, edited: NSRange(location: 19, length: 1), delta: 1,
                                                  length: (edited as NSString).length)
        #expect(span.location >= 14 && NSMaxRange(span) <= 28)                   // within the second line
    }

    @Test func openingABlockCommentRestylesToTheEnd() {
        let text = "a = 1\nb = 2\nc = 3"
        let old = SyntaxHighlighter.tokens(in: text, language: .c)
        let edited = "/*" + text
        let new = SyntaxHighlighter.tokens(in: edited, language: .c)
        let span = SyntaxHighlighter.changedRange(old: old, new: new, edited: NSRange(location: 0, length: 2), delta: 2,
                                                  length: (edited as NSString).length)
        #expect(span == NSRange(location: 0, length: (edited as NSString).length))
    }
}
