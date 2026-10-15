// Opt-in timing of code mode's colouring per keystroke (DESIGN.md §4.7): one typed or deleted character through
// `SyntaxStyler`, as the editor's storage delegate drives it, without TextKit layout (the `KeystrokeBenchmark`
// covers the whole keystroke). Markdown and Swift at 2 000, 20 000 and 32 000 units, then the work a keystroke
// leaves for the background in a long note (above `SyntaxStyler.synchronousLimit`), and a whole pass with and
// without the checkpoints `SyntaxCache` keeps. Run in Release with
//   CRANNY_SYNTAX_BENCH=/path/to/report.txt swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG \
//     --scratch-path .build-release --filter SyntaxKeystrokeBenchmark
// (`-DDEBUG` as in `KeystrokeBenchmark`.)
// Writes medians and means (µs) to the report; asserts nothing (timings depend on the machine).
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Syntax keystroke benchmark", .enabled(if: ProcessInfo.processInfo.environment["CRANNY_SYNTAX_BENCH"] != nil))
@MainActor struct SyntaxKeystrokeBenchmark {
    private static let markdown = """
        ## Release notes
        Some *emphasis* and **strong** text with `code` and [a link](https://example.com/page).
        - [ ] tag the build and ship it
        ```swift
        let retries = 3 // flaky CI
        func greet(_ name: String) -> String { "Hi \\(name)" }
        ```
        > a quote with https://cranny.app

        """
    private static let swift = """
        /// Loads the note and keeps its colours.
        @MainActor final class Loader {
            private var cache: [String: Int] = [:]
            func load(_ name: String, retries: Int = 3) async throws -> Int {
                if let hit = cache[name] { return hit }   // fast path
                let value = try await fetch(name, attempt: retries * 2 + 1)
                cache[name] = value
                return value
            }
        }

        """

    private static func text(_ block: String, units: Int) -> String {
        let length = (block as NSString).length
        return String(repeating: block, count: max(units / length, 1))
    }

    /// Calls the styler from `didProcessEditing`, as `EditorCoordinator` does.
    private final class Delegate: NSObject, NSTextStorageDelegate {
        let styler: SyntaxStyler
        init(_ styler: SyntaxStyler) { self.styler = styler }
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            styler.textChanged(TextEdit(range: editedRange, delta: delta))
        }
    }

    private static func microseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12
    }

    /// Per-keystroke µs (median, mean) of typing "x" and deleting it again at spread-out places, with and without
    /// the styler attached (the difference is the colouring's share). No run loop turns here, so the styler writes
    /// a keystroke's whole restyle at once (the app spreads a long one over frames): the mean is all the work.
    private func measure(_ text: String, _ language: CodeLanguage, styled: Bool) -> (median: Double, mean: Double) {
        let attributes = EditorAttributes(style: EditorStyle(theme: CrannyTheme(), mode: .code))
        let styler = SyntaxStyler(tokensPerSlice: 1_000_000)
        let storage = NSTextStorage(string: text)
        let delegate = Delegate(styler)
        if styled {
            storage.delegate = delegate
            styler.attach(to: storage)
            styler.restyleAll(code: true, language: language, attributes: attributes)
        }
        let clock = ContinuousClock()
        var samples: [Double] = []
        let length = storage.length
        for round in 0..<3 {
            for k in 1..<64 {
                // A place inside a line (not at its start), spread over the whole note.
                var location = length * k / 64 + round
                let ns = storage.mutableString
                while location < length && SourceText.isNewline(ns.character(at: location)) { location += 1 }
                samples.append(Self.microseconds(clock.measure {
                    storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
                }))
                samples.append(Self.microseconds(clock.measure {
                    storage.replaceCharacters(in: NSRange(location: location, length: 1), with: "")
                }))
            }
        }
        withExtendedLifetime(delegate) {}
        let sorted = samples.sorted()
        return (sorted[sorted.count / 2], samples.reduce(0, +) / Double(samples.count))
    }

    /// The off-main work one typed character costs in a long note: bring the styler's cache up to the snapshot and
    /// work out the changed range (`SyntaxHighlighter.restyle`). The styler still holds the cache, so its arrays are
    /// copied first, as in the app.
    private func background(_ text: String, _ language: CodeLanguage) -> Double {
        let cache = SyntaxCache(source: SourceText(text), language: language)
        let clock = ContinuousClock()
        var samples: [Double] = []
        let ns = text as NSString
        for k in 1..<32 {
            var location = ns.length * k / 32
            while location < ns.length && SourceText.isNewline(ns.character(at: location)) { location += 1 }
            let edited = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: "x") as NSString
            let edit = TextEdit(range: NSRange(location: location, length: 1), delta: 1)
            let source = SourceText(edited)
            samples.append(Self.microseconds(clock.measure {
                var updated = cache
                let change = updated.apply(edit, source: source)
                _ = updated.changedRange(change, edit: edit)
            }))
        }
        return samples.sorted()[samples.count / 2]
    }

    @Test func report() throws {
        var lines = ["typed/deleted character through SyntaxStyler (µs: median / mean; storage alone in brackets)"]
        for (name, block, language) in [("markdown", Self.markdown, CodeLanguage.markdown), ("swift", Self.swift, .swift)] {
            for units in [2_000, 20_000, 32_000] {
                let text = Self.text(block, units: units)
                _ = measure(text, language, styled: true)                                   // warm up
                let styled = measure(text, language, styled: true)
                let bare = measure(text, language, styled: false)
                lines.append("\(name) \((text as NSString).length)u: \(String(format: "%.1f / %.1f", styled.median, styled.mean))"
                    + " [\(String(format: "%.1f / %.1f", bare.median, bare.mean))]")
            }
        }
        for (name, block, language) in [("markdown", Self.markdown, CodeLanguage.markdown), ("swift", Self.swift, .swift)] {
            let cells = [100_000, 290_000].map { units in
                let text = Self.text(block, units: units)
                _ = background(text, language)                                          // warm up
                return "\((text as NSString).length)u \(String(format: "%.1f", background(text, language)))"
            }
            lines.append("background work per typed character, \(name) (µs, median): " + cells.joined(separator: " · "))
        }
        // A whole pass (a note opens, a paste, undo or redo): the tokens alone and with the checkpoints the cache keeps.
        let clock = ContinuousClock()
        for (name, block, language) in [("markdown", Self.markdown, CodeLanguage.markdown), ("swift", Self.swift, .swift)] {
            let source = SourceText(Self.text(block, units: 32_000))
            var plain: [Double] = [], recording: [Double] = []
            for _ in 0..<15 {
                plain.append(Self.microseconds(clock.measure { _ = SyntaxHighlighter.tokens(in: source, language: language) }))
                recording.append(Self.microseconds(clock.measure { _ = SyntaxCache(source: source, language: language) }))
            }
            lines.append("whole pass, \(name) \(source.count)u (µs, median): tokens \(String(format: "%.0f", plain.sorted()[7]))"
                + " · with checkpoints \(String(format: "%.0f", recording.sorted()[7]))")
        }
        let report = lines.joined(separator: "\n") + "\n"
        let path = ProcessInfo.processInfo.environment["CRANNY_SYNTAX_BENCH"] ?? "/dev/null"
        try Data(report.utf8).write(to: URL(fileURLWithPath: path))
    }
}
