// The keystroke path (DESIGN.md §4.7, review of WP5): merged edits, the syntax styler's synchronous, background and
// sliced writes against a full pass, and incremental line numbers.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

/// A random edit of `text`: the new text and the edit as `NSTextStorage` reports it.
private func randomEdit(of text: NSString, pieces: [String], using generator: inout SeededGenerator)
    -> (text: NSString, edit: TextEdit, replaced: NSRange, inserted: String) {
    let location = Int.random(in: 0...text.length, using: &generator)
    let removed = Int.random(in: 0...2, using: &generator) == 0 ? min(Int.random(in: 0...8, using: &generator), text.length - location) : 0
    let inserted = Int.random(in: 0...4, using: &generator) == 0 ? "" : pieces[Int.random(in: 0..<pieces.count, using: &generator)]
    let replaced = NSRange(location: location, length: removed)
    let length = (inserted as NSString).length
    return (text.replacingCharacters(in: replaced, with: inserted) as NSString,
            TextEdit(range: NSRange(location: location, length: length), delta: length - removed), replaced, inserted)
}

@Suite("Merged edits") struct TextEditTests {
    @Test func aMergedEditDescribesTheWholeBurst() {
        var generator = SeededGenerator(seed: 0x7E57)
        for round in 0..<3_000 {
            let original = String((0..<Int.random(in: 0...30, using: &generator)).map { _ in "ab\n".randomElement(using: &generator) ?? "a" })
                as NSString
            var text = original
            var merged: TextEdit?
            for _ in 0..<Int.random(in: 1...6, using: &generator) {
                let step = randomEdit(of: text, pieces: ["x", "yz", "\n", "", "long piece"], using: &generator)
                text = step.text
                merged = merged.map { $0.followed(by: step.edit) } ?? step.edit
            }
            guard let edit = merged else { continue }
            // Before the merged edit nothing changed; after it everything is the old text, shifted by `delta`.
            #expect(edit.range.location >= 0 && NSMaxRange(edit.range) <= text.length, "round \(round)")
            #expect(edit.oldEnd >= edit.range.location && edit.oldEnd <= original.length, "round \(round)")
            #expect(text.length - original.length == edit.delta, "round \(round)")
            #expect(text.substring(to: edit.range.location) == original.substring(to: edit.range.location), "round \(round)")
            #expect(text.substring(from: NSMaxRange(edit.range)) == original.substring(from: edit.oldEnd), "round \(round) \(edit)")
        }
    }
}

/// Calls the styler from `didProcessEditing`, as `EditorCoordinator` does.
@MainActor private final class StorageDelegate: NSObject, NSTextStorageDelegate {
    let styler: SyntaxStyler
    init(_ styler: SyntaxStyler) { self.styler = styler }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        styler.textChanged(TextEdit(range: editedRange, delta: delta))
    }
}

@Suite("Syntax styler") @MainActor struct SyntaxStylerTests {
    private let attributes = EditorAttributes(style: EditorStyle(theme: CrannyTheme(), mode: .code))

    /// The storage a full pass would leave: base everywhere, then each token's attributes.
    private func expectedStorage(_ text: String, _ language: CodeLanguage?) -> NSTextStorage {
        let storage = NSTextStorage(string: text, attributes: attributes.base)
        for token in SyntaxHighlighter.tokens(in: text, language: language) {
            storage.setAttributes(attributes.attributes(for: token.kind), range: token.range)
        }
        return storage
    }

    /// The first index whose attributes differ, or nil.
    private func firstDifference(_ a: NSTextStorage, _ b: NSTextStorage) -> Int? {
        guard a.length == b.length else { return 0 }
        return (0..<a.length).first { i in
            !NSDictionary(dictionary: a.attributes(at: i, effectiveRange: nil)).isEqual(to: b.attributes(at: i, effectiveRange: nil))
        }
    }

    private func settle(_ styler: SyntaxStyler) async throws {
        for _ in 0..<2_000 where styler.isRestyling { try await Task.sleep(for: .milliseconds(1)) }
        #expect(!styler.isRestyling)
    }

    /// Random edits with the work after them interleaved at random: once it settles, the storage shows exactly
    /// what a full pass shows — synchronously re-tokenized, in the background, and written in tiny slices.
    @Test(arguments: [(Int.max, 1_000), (0, 1_000), (Int.max, 2), (0, 3), (120, 4)])
    func editsEndInTheColoursOfAFullPass(_ limits: (synchronous: Int, slice: Int)) async throws {
        let pieces = ["a", " ", "\n", "\"", "/*", "*/", "//", "`", "```", "#", "<", ">", "{", "}", "1", "x = \"y\"", "# h\n", "*"]
        for (index, (language, sample)) in languageSamples.enumerated() {
            var generator = SeededGenerator(seed: 0x5717 + UInt64(index))
            let styler = SyntaxStyler(synchronousLimit: limits.synchronous, tokensPerSlice: limits.slice, pause: .zero)
            let storage = NSTextStorage(string: sample)
            let delegate = StorageDelegate(styler)
            storage.delegate = delegate
            styler.attach(to: storage)
            styler.restyleAll(code: true, language: language, attributes: attributes)
            var text = sample as NSString
            for _ in 0..<40 {
                let step = randomEdit(of: text, pieces: pieces, using: &generator)
                storage.replaceCharacters(in: step.replaced, with: step.inserted)  // inherits neighbouring attributes
                text = step.text
                for _ in 0..<Int.random(in: 0...3, using: &generator) { await Task.yield() }
            }
            try await settle(styler)
            let expected = expectedStorage(storage.string, language)
            let difference = firstDifference(storage, expected)
            #expect(difference == nil, "language \(language?.rawValue ?? "generic"), first difference at \(difference ?? -1)")
            #expect(styler.tokens == SyntaxHighlighter.tokens(in: storage.string, language: language))
            withExtendedLifetime(delegate) {}
        }
    }

    @Test func aLongNoteIsTokenizedOffTheKeystroke() async throws {
        let styler = SyntaxStyler(synchronousLimit: 10, tokensPerSlice: 1_000, pause: .zero)
        let storage = NSTextStorage(string: "let a = 1 // one\nlet b = 2\n")
        let delegate = StorageDelegate(styler)
        storage.delegate = delegate
        styler.attach(to: storage)
        styler.restyleAll(code: true, language: .swift, attributes: attributes)
        #expect(styler.tokens.isEmpty)                                          // longer than the limit: not yet
        try await settle(styler)
        #expect(firstDifference(storage, expectedStorage(storage.string, .swift)) == nil)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "/* ")
        #expect(styler.isRestyling)                                             // the keystroke only queued work
        try await settle(styler)
        #expect(firstDifference(storage, expectedStorage(storage.string, .swift)) == nil)
        withExtendedLifetime(delegate) {}
    }

    @Test func aLongRestyleIsWrittenInSlices() async throws {
        let text = String(repeating: "let x = 1\n", count: 50)
        let all = SyntaxHighlighter.tokens(in: text, language: .swift)
        #expect(all.count == 100)                                               // `let` and `1` on every line
        let styler = SyntaxStyler(synchronousLimit: .max, tokensPerSlice: 40, pause: .zero)
        let storage = NSTextStorage(string: text)
        styler.attach(to: storage)
        styler.restyleAll(code: true, language: .swift, attributes: attributes)
        #expect(styler.tokens == Array(all.prefix(40)))                         // the first slice now, the rest later
        #expect(styler.isRestyling)
        try await settle(styler)
        #expect(styler.tokens == all)
        #expect(firstDifference(storage, expectedStorage(text, .swift)) == nil)
    }

    @Test func plainModeKeepsOneStyle() {
        let styler = SyntaxStyler()
        let storage = NSTextStorage(string: "let x = 1 // not code here")
        let delegate = StorageDelegate(styler)
        storage.delegate = delegate
        styler.attach(to: storage)
        let plain = EditorAttributes(style: EditorStyle(theme: CrannyTheme(), mode: .plain))
        styler.restyleAll(code: false, language: .swift, attributes: plain)
        storage.replaceCharacters(in: NSRange(location: 3, length: 0), with: "\"")
        #expect(styler.tokens.isEmpty && !styler.isRestyling)
        var range = NSRange()
        _ = storage.attributes(at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
        #expect(range.length == storage.length)                                 // one run of base attributes
        withExtendedLifetime(delegate) {}
    }
}

@Suite("Incremental line numbers") struct LineStartTests {
    @Test func incrementalLineStartsMatchAFullScan() {
        var generator = SeededGenerator(seed: 0x11E5)
        let pieces = ["a", "bc", "\n", "\r", "\r\n", "\u{2028}", "x\ny", "\n\n", "😀"]
        var text = "one\r\ntwo\rthree\n" as NSString
        var starts = LineNumberRuler.lineStarts(in: text)
        for step in 0..<3_000 {
            let edit = randomEdit(of: text, pieces: pieces, using: &generator)
            text = edit.text
            starts = LineNumberRuler.lineStarts(starts, after: edit.edit, in: text)
            let full = LineNumberRuler.lineStarts(in: text)
            #expect(starts == full, "step \(step), \(edit.edit), text \((text as String).debugDescription)")
            if starts != full { return }
        }
    }
}
