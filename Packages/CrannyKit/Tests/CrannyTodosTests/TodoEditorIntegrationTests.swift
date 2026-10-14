import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

/// The title editor inside the real widget, in an offscreen window that is never ordered in: focus, typing and
/// the field editor's key-binding commands (↩, ⌘↑, Esc, ⌫) reach the model as they do in the panel.
@MainActor
struct TodoEditorIntegrationTests {
    let services = CrannyServices.testing()

    /// Records the keys nothing inside handled: they reached the end of the responder chain, where the shell's
    /// Esc chain (WP12) closes the panel.
    final class RecordingWindow: NSWindow {
        var unhandledKeyCodes: [UInt16] = []
        override func keyDown(with event: NSEvent) { unhandledKeyCodes.append(event.keyCode) }
    }

    private func host(_ model: TodosModel, isFocused: Bool = false) -> (RecordingWindow, NSHostingView<some View>) {
        let theme = CrannyTheme()
        let grid = theme.grid
        let view = TodosView(model: model, context: WidgetContext(
            cells: 3, contentSize: CGSize(width: grid.width(cells: 3) - 24, height: grid.height - 24), isFocused: isFocused))
            .crannyCard(cells: 3)
            .crannyThemeRoot(theme)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = RecordingWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        return (window, host)
    }

    /// Esc as the keyboard sends it, dispatched in process (`NSWindow.sendEvent`; nothing reaches the system).
    private func pressEscape(in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil,
                                                       characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                                       isARepeat: false, keyCode: 53))
            window.sendEvent(event)
        }
    }

    /// Lets SwiftUI update and the editor focus itself (it does so on the next main-actor turn).
    private func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private func editor(_ window: NSWindow) -> NSTextView? { window.firstResponder as? NSTextView }

    @Test func theEditorFocusesItselfAndTypingReachesTheModel() async throws {
        let model = TodosModel.testing([Todo(title: "a")], services: services)
        let (window, host) = host(model)
        let id = model.beginNew(after: nil)
        try await settle(host)
        let field = try #require(editor(window))
        #expect((services.notch as? PreviewNotchControl)?.calls.contains("key") == true)   // panel made key
        field.insertText("buy milk", replacementRange: field.selectedRange())
        #expect(model.item(id)?.title == "buy milk")
        window.contentView = nil
    }

    @Test func returnStartsTheNextRowAndMovesTheEditorThere() async throws {
        let model = TodosModel.testing([Todo(title: "a"), Todo(title: "b")], services: services)
        let (window, host) = host(model)
        let a = model.items[0].id
        model.beginEditing(a)
        try await settle(host)
        try #require(editor(window)).doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let draft = try #require(model.editingID)
        #expect(draft != a)
        try await settle(host)
        let field = try #require(editor(window))                // the new row's editor took over
        field.insertText("c", replacementRange: field.selectedRange())
        #expect(model.items.map(\.title) == ["a", "c", "b"])
        window.contentView = nil
    }

    @Test func commandArrowReordersWithoutLeavingTheEditor() async throws {
        let model = TodosModel.testing([Todo(title: "a"), Todo(title: "b")], services: services)
        let (window, host) = host(model)
        let b = model.items[1].id
        model.beginEditing(b)
        try await settle(host)
        try #require(editor(window)).doCommand(by: #selector(NSResponder.moveToBeginningOfDocument(_:)))
        try await settle(host)
        #expect(model.items.map(\.title) == ["b", "a"])
        #expect(model.editingID == b)
        #expect(editor(window) != nil)
        window.contentView = nil
    }

    /// The contract the shell's Esc chain relies on (DESIGN.md §16 "Esc closes, after leaving …"): while a title
    /// is edited, Esc stops editing and goes no further; the next Esc is not the widget's and travels on to close.
    @Test func escapeStopsEditingAndOnlyTheNextEscapeTravelsOn() async throws {
        let model = TodosModel.testing([Todo(title: "a")], services: services)
        let (window, host) = host(model, isFocused: true)
        let a = model.items[0].id
        model.beginEditing(a)
        try await settle(host)
        #expect(editor(window) != nil)
        try pressEscape(in: window)
        #expect(model.editingID == nil)
        #expect(window.unhandledKeyCodes.isEmpty)               // consumed by the editor
        try await settle(host)
        #expect(model.selectionRequest == nil)                 // the list took the request: "a" is selected
        try pressEscape(in: window)
        #expect(window.unhandledKeyCodes == [53])               // not the list's: the shell may close now
        window.contentView = nil
    }

    @Test func deleteBackwardOnAnEmptyDraftReturnsToTheRowAbove() async throws {
        let model = TodosModel.testing([Todo(title: "a")], services: services)
        let (window, host) = host(model)
        let a = model.items[0].id
        model.beginNew(after: a)
        try await settle(host)
        try #require(editor(window)).doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(model.items.map(\.title) == ["a"])
        #expect(model.editingID == a)
        try await settle(host)
        #expect(editor(window) != nil)
        window.contentView = nil
    }
}
