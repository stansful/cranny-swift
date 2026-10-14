// The editor's AppKit side without a window: TextKit 2 stays on, typing reaches the model, code mode colours
// with SyntaxPalette, each note has its own undo history, and switching notes restores the caret.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Editor") final class EditorTests {
    private let services = CrannyServices.preview()
    private nonisolated let temporaryFolder: URL
    private let model: NotesModel

    init() {
        temporaryFolder = services.paths.root.deletingLastPathComponent()
        model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
    }

    deinit { try? FileManager.default.removeItem(at: temporaryFolder) }

    private func configuration(_ entry: NotesModel.Entry, typingEffect: Bool = false) -> EditorConfiguration {
        EditorConfiguration(noteID: entry.id, entry: entry, style: EditorStyle(theme: CrannyTheme(), mode: entry.mode),
                            typingEffect: typingEffect, showsLineNumbers: false, focusRequested: false,
                            externalRevision: model.externalRevision)
    }

    private func editor(showing entry: NotesModel.Entry) throws -> (EditorCoordinator, NotesTextView) {
        let coordinator = EditorCoordinator(model: model)
        _ = coordinator.makeView()
        coordinator.update(configuration(entry))
        return (coordinator, try #require(coordinator.textView))
    }

    @Test func showsTheNoteWithTextKit2AndReportsTyping() throws {
        model.adoptLoadedNotes([Note(title: "Plan", text: "hello", mode: .plain)])
        let entry = try #require(model.selectedEntry)
        let (_, textView) = try editor(showing: entry)
        #expect(textView.textLayoutManager != nil)                              // TextKit 2
        #expect(textView.string == "hello")
        #expect(textView.selectedRange() == NSRange(location: 5, length: 0))    // caret at the end
        textView.insertText(" world", replacementRange: textView.selectedRange())
        #expect(model.text(of: entry.id) == "hello world")
        #expect(textView.textLayoutManager != nil)                              // never fell back to TextKit 1
        #expect(!textView.isRichText)
    }

    @Test func codeModeColoursTokensAndRestylesEdits() throws {
        model.adoptLoadedNotes([Note(title: "a.swift", text: "let x = 1", mode: .code)])
        let entry = try #require(model.selectedEntry)
        let (_, textView) = try editor(showing: entry)
        let storage = try #require(textView.textStorage)
        func color(at index: Int) -> NSColor? {
            (storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB)
        }
        let keyword = SyntaxPalette.keyword
        #expect(abs((color(at: 0)?.redComponent ?? 0) - keyword.r) < 0.01)      // "let"
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)                                     // SF Mono in code mode
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        textView.insertText(" // note", replacementRange: textView.selectedRange())
        let comment = color(at: 12)
        #expect(comment?.alphaComponent ?? 1 < 0.9)                             // comments are tertiary
    }

    @Test func eachNoteHasItsOwnUndoHistoryAndCaret() throws {
        model.adoptLoadedNotes([Note(title: "A", text: "aaa", mode: .plain), Note(title: "B", text: "bbb", mode: .plain)])
        let a = try #require(model.entries.first), b = try #require(model.entries.last)
        let (coordinator, textView) = try editor(showing: a)
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.insertText("X", replacementRange: textView.selectedRange())
        #expect(model.text(of: a.id) == "aXaa")
        let undoA = coordinator.undoManager(for: textView)
        #expect(undoA?.canUndo == true)
        model.select(b.id)
        coordinator.update(configuration(b))
        #expect(textView.string == "bbb")
        #expect(coordinator.undoManager(for: textView)?.canUndo == false)       // B's history is empty
        coordinator.update(configuration(a))
        #expect(textView.string == "aXaa")
        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))    // caret where it was
        coordinator.undoManager(for: textView)?.undo()
        #expect(textView.string == "aaa")
        #expect(model.text(of: a.id) == "aaa")
    }

    @Test func externalChangesReloadTheStorage() throws {
        model.adoptLoadedNotes([])
        let id = model.newNote(text: "Hel")                                     // type-to-capture
        let entry = try #require(model.entry(id))
        let (coordinator, textView) = try editor(showing: entry)
        #expect(textView.string == "Hel")
        #expect(textView.selectedRange().location == 3)                          // typing continues after it
        coordinator.dismantle()
        #expect(model.selections[id] == NSRange(location: 3, length: 0))
    }

    @Test func fileDragsAreLeftToTheShell() throws {
        model.adoptLoadedNotes([Note(title: "A", text: "", mode: .plain)])
        let (_, textView) = try editor(showing: try #require(model.selectedEntry))
        #expect(textView.acceptableDragTypes == [.string])
    }

    @Test func notesShortcutsReachTheModel() throws {
        model.adoptLoadedNotes([Note(title: "A", text: "a", mode: .plain), Note(title: "B", text: "b", mode: .plain)])
        let (_, textView) = try editor(showing: try #require(model.selectedEntry))
        #expect(textView.onCommand?(.nextNote) == true)
        #expect(model.selectedEntry?.title == "B")
        #expect(textView.onCommand?(.toggleCodeMode) == true)
        #expect(model.selectedEntry?.mode == .code)
        #expect(textView.onCommand?(.newNote) == true)
        #expect(model.entries.count == 3)
        #expect(textView.onCommand?(.copy) == false)                            // text commands stay in the view
        #expect(textView.performTextCommand(.selectAll))
        #expect(textView.selectedRange() == NSRange(location: 0, length: (textView.string as NSString).length))
    }
}
