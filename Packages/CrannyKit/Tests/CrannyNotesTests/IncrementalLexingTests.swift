// `SyntaxCache`: after every edit the incrementally updated tokens (and resume points) must be exactly those of a full
// pass — for every language and for Markdown with fences of every language, over thousands of seeded random edits
// that open and close comments, strings, template literals, tags, bodies, block scalars and fences. A longer run with
// n seeds per document, by hand after changing a tokenizer (400: ≈ 10 min in Release on an M4 Max):
//   CRANNY_LEXING_ROUNDS=400 swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG \
//     --scratch-path .build-release --filter IncrementalLexingTests
import Foundation
import Testing
@testable import CrannyNotes

/// Markdown documents whose fences switch languages (nested Markdown, HTML with script and style, CRLF lines).
nonisolated private let fencedDocuments: [String] = [
    "# Notes\n\n```swift\nlet a = 1 /* open\nstill */\nlet s = \"\"\"\nmulti\n\"\"\"\n```\n\nText *em* `code` [l](u)\n\n"
        + "~~~python\ndef f():\n    '''doc\n    '''\n~~~\n",
    "```html\n<div class=\"a\"\n  id=b>\n<script>\nconst t = `x\n${y}`; /* c\n*/\n</script>\n<style>\np { color: red;\n"
        + "  margin: 0 }\n.a {\n  b: c;\n}\n</style>\n</div>\n```\n- item\n```css\n.a {\n  b: c;\n  p:hover { x: 1 }\n}\n```\n",
    "````markdown\n# inner\n```js\nlet a = `1\n2`\n```\n```html\n<script>let x = 1</script>\n```\n````\n\n```yaml\nkey: |\n"
        + "  text\n  more\nnext: 1\n```\n```json\n{\n  \"a\"\n\n  : 1, \"b\": [1, 2]\n}\n```\n",
    "```\nunknown \"str\" /* c */\n```\n  ```rust\n  fn main() { r#\"raw\n\"# }\n  ```\n```sh\necho \"a\nb\" 'c\nd'\n```\n"
        + "```sql\nselect 'a\nb' -- c\n```\n```go\nx := `raw\nraw`\n```\n",
    "Intro\r\n```c\r\nint a; /* x\r\n y */\r\n```\r\n> quote\r\n```kotlin\r\nval s = \"\"\"\r\nk\r\n\"\"\"\r\n```\r\n",
    "```cpp\nauto r = R\"(raw\n)\";\n```\n```ruby\nputs \"a\" # c\n```\n```objc\n@interface A\n@end\n```\n"
        + "```java\nString s = \"\"\"\nj\n\"\"\";\n```\n```typescript\nlet t: string = `a\n${b}`\n```\n",
]

/// Pieces the random edits insert: openers and closers of every multi-line construct, line ends of every kind.
nonisolated private let editPieces = [
    "a", "x", " ", "  ", "    ", "\t", "\n", "\n", "\n\n", "\r\n", "\r", "\u{2028}", "😀", "я", "1", "0x", ".", "-", "_",
    "\"", "'", "`", "\\", "/", "*", "#", "//", "/*", "*/", "\"\"\"", "'''", "#\"", "\"#", "r#\"", "R\"(", ")\"", "${", "$",
    "{", "}", "(", ")", "[", "]", "](", ";", ":", "<", ">", "</", "<!--", "-->", "<![CDATA[", "]]>", "<?", "?>", "&amp;",
    "<script>", "</script>", "<style>", "</style>", "<div a=\"", "```", "```\n", "\n```\n", "~~~", "````", "```swift\n",
    "```html\n", "```css\n", "```md\n", "```json\n", "```yaml\n", "```js\n", "```python\n", "\n```", "# h\n", "> ", "- ",
    "- [ ] ", "1. ", "**", "_", "key: |\n", "key: >-\n", "- \"v\"\n", "--", "---\n", "@a", "p:hover {", "color: red;",
    "!important", "x = \"y\"\n", "/* c */", "\"k\": ", "\"k\"\n", "\n:", "true", "let", "fn", "def",
]

/// Small documents whose decisions look across lines (a JSON key's `:` lines later, a CSS rule's `{`, a body's end):
/// every single edit at every place is checked.
nonisolated private let trickyDocuments: [(CodeLanguage?, String)] = [
    (.json, "{\n  \"a\"\n\n  : 1,\n  \"b\"\n  :\n  [\"c\"\n  ,\n  \"d\"\n\n  ]\n}\n"),
    (.css, ".a\n{\n  color: red\n}\n.b { c: d; e: f }\np\n:hover\n{ x: 1;\n  y\n  { z: 2 } }\n"),
    (.markdown, "```json\n\"k\"\n\n```\n```css\na\nb\n```\nx\n```\n\"s\"\n"),
    (.markdown, "```json\n\"k\"\n\n   ```\n~~~css\na\n\n  ~~~\ny\n"),        // looks that reach an indented closing line
    (.html, "<style>\na\n{ b: c }</style>\n<script>\nlet a = `\n`</script>\n<p\nclass=\"x\">\n"),
    (.html, "<style>\np { b: c }\n</style>\n<script>\nlet a = 1\n</script>\n<p>\n"),        // bodies closed at a line start
    (.markdown, "```json\n\"k\"\n\n```x\n\"v\"\n```\n"),                                // an edit after the look makes it closing
    (.yaml, "a: |\n  b\n   c\nd: >-\n  e\n\nf: 1\n"),
    (.swift, "/* a\n*/ let s = \"\"\"\nb\n\"\"\" // c\n\"d\\\ne\"\n"),
]

/// Every language (and generic code) with its sample, then the fenced Markdown documents.
nonisolated private let documents: [(CodeLanguage?, String)] = languageSamples + fencedDocuments.map { (.markdown, $0) }

/// Seeds per document for the random edits (one by default).
nonisolated private let rounds = ProcessInfo.processInfo.environment["CRANNY_LEXING_ROUNDS"].flatMap { Int($0) } ?? 1

@Suite("Incremental lexing") struct IncrementalLexingTests {
    private struct Mismatch: Error, CustomStringConvertible {
        var description: String
    }

    /// The cache after an update must be the cache a full pass makes, and its changed range the whole lists' one.
    private func check(_ cache: SyntaxCache, _ change: SyntaxCache.Change, edit: TextEdit, old: [SyntaxToken],
                       text: NSString, language: CodeLanguage?, step: Int) throws {
        let full = SyntaxCache(source: SourceText(text), language: language)
        let context = "language \(language?.rawValue ?? "generic"), step \(step), \(edit), text \((text as String).debugDescription)"
        guard cache.source.units == full.source.units else { throw Mismatch(description: "source differs: \(context)") }
        guard cache.tokens == full.tokens else {
            let first = cache.tokens.indices.first { $0 >= full.tokens.count || cache.tokens[$0] != full.tokens[$0] } ?? cache.tokens.count
            throw Mismatch(description: "tokens differ at \(first): \(cache.tokens.dropFirst(first).prefix(3)) vs "
                + "\(full.tokens.dropFirst(first).prefix(3)); \(context)")
        }
        guard cache.checkpoints == full.checkpoints else {
            let first = cache.checkpoints.indices.first {
                $0 >= full.checkpoints.count || cache.checkpoints[$0] != full.checkpoints[$0]
            } ?? cache.checkpoints.count
            throw Mismatch(description: "checkpoints differ at \(first): \(cache.checkpoints.dropFirst(first).prefix(2)) vs "
                + "\(full.checkpoints.dropFirst(first).prefix(2)); \(context)")
        }
        let span = cache.changedRange(change, edit: edit)
        let expected = SyntaxHighlighter.changedRange(old: old, new: full.tokens, edit: edit, length: text.length)
        guard span == expected else { throw Mismatch(description: "changed range \(span) vs \(expected); \(context)") }
    }

    /// A random edit: where, how much is removed, what is inserted.
    private func randomEdit(of text: NSString, using generator: inout SeededGenerator) -> (NSString, TextEdit) {
        let length = text.length
        let location = Int.random(in: 0...length, using: &generator)
        let shrink = length > 700                                               // keep the documents small
        let removed = Int.random(in: 0...(shrink ? 1 : 2), using: &generator) == 0 || shrink
            ? min(Int.random(in: 0...(shrink ? 40 : 10), using: &generator), length - location) : 0
        let inserted = Int.random(in: 0...5, using: &generator) == 0 ? ""
            : editPieces[Int.random(in: 0..<editPieces.count, using: &generator)]
        let insertedLength = (inserted as NSString).length
        let next = text.replacingCharacters(in: NSRange(location: location, length: removed), with: inserted) as NSString
        return (next, TextEdit(range: NSRange(location: location, length: insertedLength), delta: insertedLength - removed))
    }

    /// Single edits applied from the text storage's string, and bursts of edits merged into one and applied from a
    /// snapshot, as the styler does for long notes.
    @Test(arguments: documents.indices)
    func everyUpdateEqualsAFullPass(_ index: Int) throws {
        for round in 0..<max(rounds, 1) {
            let seed = 0x1E8E5 + UInt64(index) + UInt64(round) << 32
            do { try randomEdits(documents[index], seed: seed) } catch { throw Mismatch(description: "seed \(seed): \(error)") }
        }
    }

    private func randomEdits(_ document: (CodeLanguage?, String), seed: UInt64) throws {
        let (language, sample) = document
        var generator = SeededGenerator(seed: seed)
        var text = sample as NSString
        var cache = SyntaxCache(source: SourceText(text), language: language)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: sample, language: language))
        var step = 0
        while step < 2_500 {
            let old = cache.tokens
            if Int.random(in: 0..<8, using: &generator) == 0 {
                var merged: TextEdit?
                for _ in 0..<Int.random(in: 2...4, using: &generator) {
                    let (next, edit) = randomEdit(of: text, using: &generator)
                    text = next
                    merged = merged.map { $0.followed(by: edit) } ?? edit
                    step += 1
                }
                guard let merged else { continue }
                let change = cache.apply(merged, source: SourceText(text))
                try check(cache, change, edit: merged, old: old, text: text, language: language, step: step)
            } else {
                let (next, edit) = randomEdit(of: text, using: &generator)
                text = next
                step += 1
                let change = cache.apply(edit, from: text)
                try check(cache, change, edit: edit, old: old, text: text, language: language, step: step)
            }
        }
    }

    /// Every deletion of one unit and every insertion of a few pieces, at every place of a small document.
    @Test(arguments: trickyDocuments.indices)
    func everySingleEditEqualsAFullPass(_ index: Int) throws {
        let (language, sample) = trickyDocuments[index]
        let text = sample as NSString
        let base = SyntaxCache(source: SourceText(text), language: language)
        var step = 0
        for location in 0...text.length {
            var edits: [(NSRange, String)] = ["\n", ":", "{", "\"", "`", "```\n", "</style>", "x"].map {
                (NSRange(location: location, length: 0), $0)
            }
            if location < text.length { edits.append((NSRange(location: location, length: 1), "")) }
            for (replaced, inserted) in edits {
                let next = text.replacingCharacters(in: replaced, with: inserted) as NSString
                let length = (inserted as NSString).length
                let edit = TextEdit(range: NSRange(location: location, length: length), delta: length - replaced.length)
                var cache = base
                let change = cache.apply(edit, from: next)
                step += 1
                try check(cache, change, edit: edit, old: base.tokens, text: next, language: language, step: step)
            }
        }
    }

    /// The pass that records checkpoints gives the same tokens as the plain one.
    @Test(arguments: documents.indices)
    func recordingDoesNotChangeTheTokens(_ index: Int) {
        let (language, sample) = documents[index]
        #expect(SyntaxCache(source: SourceText(sample), language: language).tokens
            == SyntaxHighlighter.tokens(in: sample, language: language))
    }

    /// Typing in a long note re-tokenizes the line it is on (and a few around it), not the note.
    @Test(arguments: documents.indices)
    func aKeystrokeRetokenizesItsNeighbourhood(_ index: Int) {
        let (language, sample) = documents[index]
        let block = sample.hasSuffix("\n") ? sample : sample + "\n"
        var text = String(repeating: block, count: 40) as NSString
        var cache = SyntaxCache(source: SourceText(text), language: language)
        // The middle of a line in the middle of the note.
        var location = text.length / 2
        while location < text.length && !SourceText.isNewline(text.character(at: location)) { location += 1 }
        location = max(location - 1, 0)
        text = text.replacingCharacters(in: NSRange(location: location, length: 0), with: "x") as NSString
        let change = cache.apply(TextEdit(range: NSRange(location: location, length: 1), delta: 1), from: text)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: text as String, language: language))
        #expect(change.inserted.count < cache.tokens.count / 8, "re-tokenized \(change.inserted.count) of \(cache.tokens.count)")
    }

    @Test func openingABlockCommentRetokenizesToTheEndAndClosingItComesBack() {
        let lines = String(repeating: "let a = 1 // one\n", count: 200)
        var text = lines as NSString
        var cache = SyntaxCache(source: SourceText(text), language: .swift)
        text = text.replacingCharacters(in: NSRange(location: 0, length: 0), with: "/*") as NSString
        var change = cache.apply(TextEdit(range: NSRange(location: 0, length: 2), delta: 2), from: text)
        #expect(cache.tokens == [SyntaxToken(.comment, NSRange(location: 0, length: text.length))])
        #expect(change.replaced.count == 600)
        text = text.replacingCharacters(in: NSRange(location: 0, length: 2), with: "") as NSString
        change = cache.apply(TextEdit(range: NSRange(location: 0, length: 0), delta: -2), from: text)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: lines, language: .swift))
        #expect(change.inserted.count == 600)
    }

    @Test func aFenceBodyResumesInsideTheFence() {
        let body = String(repeating: "let a = 1 // one\n", count: 200)
        var text = ("# T\n```swift\n" + body + "```\nafter *em*\n") as NSString
        var cache = SyntaxCache(source: SourceText(text), language: .markdown)
        let location = 13 + 17 * 100 + 4                                        // inside line 100 of the body
        text = text.replacingCharacters(in: NSRange(location: location, length: 0), with: "x") as NSString
        let change = cache.apply(TextEdit(range: NSRange(location: location, length: 1), delta: 1), from: text)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: text as String, language: .markdown))
        #expect(change.inserted.count <= 6, "re-tokenized \(change.inserted.count)")
    }

    @Test func notesOverTheLimitStayUncolouredAndComeBack() {
        let line = "let x = 1\n"
        var text = String(repeating: line, count: SyntaxHighlighter.maximumLength / 10) as NSString
        var cache = SyntaxCache(source: SourceText(text), language: .swift)
        #expect(!cache.tokens.isEmpty)
        text = text.replacingCharacters(in: NSRange(location: 0, length: 0), with: line) as NSString
        _ = cache.apply(TextEdit(range: NSRange(location: 0, length: 10), delta: 10), from: text)
        #expect(cache.tokens.isEmpty && cache.checkpoints.isEmpty)                // over the limit
        text = text.replacingCharacters(in: NSRange(location: 0, length: 10), with: "") as NSString
        _ = cache.apply(TextEdit(range: NSRange(location: 0, length: 0), delta: -10), from: text)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: text as String, language: .swift))
    }

    @Test func aSourceThatDoesNotMatchIsTokenizedWhole() {
        var cache = SyntaxCache(source: SourceText("let a = 1"), language: .swift)
        let text = "var b = \"x\"\nlet c = 2" as NSString                       // not "let a = 1" after the edit
        _ = cache.apply(TextEdit(range: NSRange(location: 0, length: 1), delta: 1), from: text)
        #expect(cache.tokens == SyntaxHighlighter.tokens(in: text as String, language: .swift))
        #expect(cache.source.units == Array((text as String).utf16))
    }
}
