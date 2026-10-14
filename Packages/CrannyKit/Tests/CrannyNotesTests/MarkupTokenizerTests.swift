// Highlighter tests for Markdown, HTML/XML, CSS, JSON and YAML, plus invariants every tokenizer must keep.
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Markup and data languages") struct MarkupTokenizerTests {
    @Test func markdownBlocks() {
        let h = highlights(languageSamples[0].1, .markdown)
        #expect(h.has(.marker, "#"))
        #expect(h.has(.heading, "Title"))
        #expect(h.has(.marker, ">"))
        #expect(h.has(.marker, "-"))
        #expect(h.has(.marker, "1."))
        #expect(highlights("---\ntext", .markdown).has(.marker, "---"))
        #expect(highlights("- [x] done", .markdown).has(.marker, "[x]"))
        #expect(highlights("####### seven", .markdown).leavesPlain("seven"))    // not a heading
    }

    @Test func markdownInline() {
        let h = highlights(languageSamples[0].1, .markdown)
        #expect(h.has(.emphasis, "emphasis"))
        #expect(h.has(.strong, "strong"))
        #expect(h.has(.code, "`code`"))
        #expect(h.has(.link, "a link"))
        #expect(h.has(.marker, "](https://example.com)"))
        #expect(highlights("see https://cranny.app/docs.", .markdown).has(.link, "https://cranny.app/docs"))
        #expect(highlights("snake_case_name", .markdown).leavesPlain("case"))   // `_` inside words is not emphasis
        #expect(highlights("2 * 3 * 4", .markdown).leavesPlain("3"))            // spaced stars are not emphasis
        #expect(highlights("\\*not em\\*", .markdown).leavesPlain("not"))       // escaped
    }

    @Test func markdownFencesUseTheirLanguage() {
        let h = highlights(languageSamples[0].1, .markdown)
        #expect(h.has(.marker, "```"))
        #expect(h.has(.keyword, "swift"))                                       // the info string
        #expect(h.has(.keyword, "let"))                                         // Swift inside the fence
        #expect(h.has(.comment, "// one"))
        let unclosed = highlights("```python\ndef f(): pass", .markdown)
        #expect(unclosed.has(.keyword, "def"))
        let unknown = highlights("```\n\"s\" # not a heading\n```", .markdown)
        #expect(unknown.has(.string, "\"s\""))
        #expect(unknown.leavesPlain("not a heading"))
    }

    @Test func html() {
        let h = highlights(languageSamples[15].1, .html)
        #expect(h.has(.keyword, "<!DOCTYPE html>"))
        #expect(h.has(.keyword, "html"))
        #expect(h.has(.type, "lang"))
        #expect(h.has(.string, "\"en\""))
        #expect(h.has(.comment, "<!-- comment -->"))
        #expect(h.has(.string, "main"))                                         // unquoted attribute value
        #expect(h.has(.number, "&amp;"))
        #expect(h.has(.keyword, "const"))                                       // <script> body is JavaScript
        #expect(h.has(.type, "color"))                                          // <style> body is CSS
        #expect(highlights("<?xml version=\"1.0\"?><a/>", .html).has(.keyword, "<?xml version=\"1.0\"?>"))
    }

    @Test func css() {
        let h = highlights(languageSamples[16].1, .css)
        #expect(h.has(.comment, "/* theme */"))
        #expect(h.has(.keyword, "@media"))
        #expect(h.has(.function, ".card"))
        #expect(h.has(.function, ":hover"))
        #expect(h.has(.type, "color"))
        #expect(h.has(.number, "#1e2026"))
        #expect(h.has(.number, "-2px"))
        #expect(h.has(.number, "1.5em"))
        #expect(h.has(.string, "\"SF Pro\""))
        #expect(h.has(.keyword, "!important"))
        #expect(h.has(.function, "url"))
    }

    @Test func json() {
        let h = highlights(languageSamples[5].1, .json)
        #expect(h.has(.type, "\"name\""))                                       // keys
        #expect(h.has(.string, "\"cranny\""))                                   // values
        #expect(h.has(.number, "1.2"))
        #expect(h.has(.keyword, "true"))
        #expect(h.has(.keyword, "null"))
        #expect(h.has(.comment, "// comment"))
        #expect(h.has(.number, "-3e2"))
    }

    @Test func yaml() {
        let h = highlights(languageSamples[18].1, .yaml)
        #expect(h.has(.marker, "---"))
        #expect(h.has(.comment, "# config"))
        #expect(h.has(.type, "name"))
        #expect(h.has(.number, "1.2"))
        #expect(h.has(.keyword, "true"))
        #expect(h.has(.marker, "-"))
        #expect(h.has(.string, "\"two\""))
        #expect(h.has(.function, "&base"))
        #expect(h.has(.marker, "|"))
        #expect(h.has(.string, "line one: not a key"))                         // block scalar text, not a key
        #expect(h.has(.keyword, "~"))
        #expect(highlights("url: http://x.io/a#b", .yaml).leavesPlain("#b"))   // `#` without a space is not a comment
    }

    // MARK: Invariants

    @Test(arguments: languageSamples.indices)
    func tokensAreSortedDisjointAndInBounds(_ index: Int) {
        let (language, sample) = languageSamples[index]
        var generator = SeededGenerator(seed: UInt64(index) + 1)
        let alphabet = Array("ab1 _-*#/\\\"'`<>{}[]()$@:;.!?&=|~\n\tя😀")
        var texts = [sample]
        for _ in 0..<40 {                                                       // sample plus random noise
            var text = sample
            for _ in 0..<12 {
                let offset = Int.random(in: 0...text.count, using: &generator)
                let index = text.index(text.startIndex, offsetBy: offset)
                text.insert(alphabet[Int.random(in: 0..<alphabet.count, using: &generator)], at: index)
            }
            texts.append(text)
        }
        for text in texts {
            let tokens = SyntaxHighlighter.tokens(in: text, language: language)
            let length = (text as NSString).length
            var previousEnd = 0
            for token in tokens {
                #expect(token.range.length > 0)
                #expect(token.range.location >= previousEnd, "overlap in \(language?.rawValue ?? "generic"): \(tokens)")
                #expect(NSMaxRange(token.range) <= length)
                previousEnd = NSMaxRange(token.range)
            }
        }
    }

    @Test func veryLongTextIsNotColoured() {
        let text = String(repeating: "let x = 1\n", count: SyntaxHighlighter.maximumLength / 10 + 1)
        #expect(SyntaxHighlighter.tokens(in: text, language: .swift).isEmpty)
    }
}
