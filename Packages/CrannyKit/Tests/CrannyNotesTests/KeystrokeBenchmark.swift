// Opt-in timing of the editor's keystroke path (DESIGN.md §4.7 "no hitches at 120 Hz"): one typed character
// through the real `EditorCoordinator` in notes of growing size, in every mode. Run in Release with
//   CRANNY_NOTES_BENCH=/path/to/report.txt swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG \
//     --scratch-path .build-release --filter KeystrokeBenchmark
// (`-DDEBUG`: other targets' tests use Debug-only QA hooks; nothing on the timed path depends on it.)
// Writes medians (ms) to the report; asserts nothing (timings depend on the machine). Temporary paths only.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Keystroke benchmark", .enabled(if: ProcessInfo.processInfo.environment["CRANNY_NOTES_BENCH"] != nil))
@MainActor struct KeystrokeBenchmark {
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
    private static let russian = "Позвонить в сервис до обеда, купить лимоны и базилик, вернуть книги.\n"

    private static func text(_ block: String, units: Int) -> String {
        let length = (block as NSString).length
        return String(repeating: block, count: max(units / length, 1))
    }

    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1e3 + Double(duration.components.attoseconds) / 1e15
    }

    /// Median main-thread time of one typed character, and of opening the note (load + full restyle).
    private func keystroke(title: String, mode: NoteMode, text: String, lineNumbers: Bool = false,
                           repeats: Int = 15) throws -> (typing: Double, opening: Double) {
        let services = CrannyServices.preview()
        defer { try? FileManager.default.removeItem(at: services.paths.root.deletingLastPathComponent()) }
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        model.adoptLoadedNotes([Note(title: title, text: text, mode: mode)])
        let entry = try #require(model.selectedEntry)
        let coordinator = EditorCoordinator(model: model)
        // A real size in an offscreen window (never shown): TextKit 2 then lays out only around the viewport, as
        // in the panel. A zero-width editor would lay out every character on its own line.
        let scroll = coordinator.makeView()
        scroll.frame = NSRect(x: 0, y: 0, width: 460, height: 120)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = scroll
        defer { window.contentView = nil }
        let clock = ContinuousClock()
        let opening = clock.measure {
            coordinator.update(EditorConfiguration(noteID: entry.id, entry: entry, style: EditorStyle(theme: CrannyTheme(), mode: mode),
                                                   typingEffect: false, showsLineNumbers: lineNumbers, focusRequested: false,
                                                   externalRevision: model.externalRevision))
        }
        let textView = try #require(coordinator.textView)
        scroll.layoutSubtreeIfNeeded()
        var samples: [Double] = []
        for i in 0..<repeats {
            textView.setSelectedRange(NSRange(location: (text as NSString).length / 2 + i, length: 0))
            samples.append(Self.milliseconds(clock.measure { textView.insertText("x", replacementRange: textView.selectedRange()) }))
        }
        model.autosave.cancel()
        model.languageDetection.cancel()
        coordinator.dismantle()
        return (Self.median(samples), Self.milliseconds(opening))
    }

    @Test func report() throws {
        var lines: [String] = ["typed character, main thread (median ms) · [opening the note]"]
        for units in [2_000, 20_000, 100_000, 290_000] {
            let md = Self.text(Self.markdown, units: units)
            let ru = Self.text(Self.russian, units: units)
            let cells = [
                ("code Untitled", try keystroke(title: "Untitled", mode: .code, text: md)),
                ("code notes.md", try keystroke(title: "notes.md", mode: .code, text: md)),
                ("code Untitled ru", try keystroke(title: "Untitled", mode: .code, text: ru)),
                ("code + line numbers", try keystroke(title: "notes.md", mode: .code, text: md, lineNumbers: true)),
                ("plain", try keystroke(title: "Untitled", mode: .plain, text: md)),
            ]
            lines.append("\(units)u: " + cells.map {
                "\($0.0) \(String(format: "%.2f", $0.1.typing)) [\(String(format: "%.1f", $0.1.opening))]"
            }.joined(separator: " · "))
        }
        let clock = ContinuousClock()
        for units in [4_000, 100_000, 290_000] {
            let md = Self.text(Self.markdown, units: units)
            let ru = Self.text(Self.russian, units: units)
            let detect = Self.milliseconds(clock.measure { _ = LanguageDetector.detect(title: "Untitled", text: md) })
            let detectRussian = Self.milliseconds(clock.measure { _ = LanguageDetector.detect(title: "Untitled", text: ru) })
            let tokens = Self.milliseconds(clock.measure { _ = SyntaxHighlighter.tokens(in: md, language: .markdown) })
            lines.append("\(units)u: detect \(String(format: "%.3f", detect)) · detect ru \(String(format: "%.3f", detectRussian))"
                + " · tokens(md, full pass, off the main actor above 32k) \(String(format: "%.2f", tokens))")
        }
        let stars = String(repeating: "*x", count: 5_000) + String(repeating: "y", count: 23_896)
        let brackets = String(repeating: "[", count: 5_000) + String(repeating: "y", count: 23_896)
        let starTime = Self.milliseconds(clock.measure { _ = SyntaxHighlighter.tokens(in: stars, language: .markdown) })
        let bracketTime = Self.milliseconds(clock.measure { _ = SyntaxHighlighter.tokens(in: brackets, language: .markdown) })
        lines.append("one long line: 5000 `*x` \(String(format: "%.2f", starTime)) ms · 5000 `[` \(String(format: "%.2f", bracketTime)) ms")
        let report = lines.joined(separator: "\n") + "\n"
        let path = ProcessInfo.processInfo.environment["CRANNY_NOTES_BENCH"] ?? "/dev/null"
        try Data(report.utf8).write(to: URL(fileURLWithPath: path))
    }
}
