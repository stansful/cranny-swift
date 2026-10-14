import AppKit
import Foundation
import Testing
@testable import CrannyTodos

/// The keyboard map of DESIGN.md §7.6 / §16 (ARCHITECTURE.md §10.7 "keyboard map").
struct TodoKeyMapTests {
    let ids = [UUID(), UUID(), UUID()]

    private func command(_ key: TodoListKey, _ selection: TodoSelection?, command: Bool = false) -> TodoListCommand? {
        TodoKeyMap.command(for: key, command: command, selection: selection, visible: ids)
    }

    @Test func arrowsWalkTheRowsIncludingNewToDo() {
        #expect(command(.down, .item(ids[0])) == .select(.item(ids[1])))
        #expect(command(.down, .item(ids[2])) == .select(.newRow))
        #expect(command(.down, .newRow) == nil)                       // bottom: the key travels on
        #expect(command(.up, .newRow) == .select(.item(ids[2])))
        #expect(command(.up, .item(ids[0])) == nil)
    }

    @Test func theFirstArrowSelectsTheFirstRow() {
        #expect(command(.down, nil) == .select(.item(ids[0])))
        #expect(command(.up, nil) == .select(.item(ids[0])))
        #expect(TodoKeyMap.command(for: .down, command: false, selection: nil, visible: []) == .select(.newRow))
        #expect(command(.space, nil) == nil)
    }

    @Test func spaceToggles() {
        #expect(command(.space, .item(ids[1])) == .toggle(ids[1]))
    }

    @Test func returnEditsARowAndStartsANewToDoOnTheNewRow() {
        #expect(command(.returnKey, .item(ids[1])) == .edit(ids[1]))
        #expect(command(.returnKey, .newRow) == .newItem)
        #expect(command(.space, .newRow) == .newItem)
    }

    @Test func commandArrowsReorder() {
        #expect(command(.up, .item(ids[1]), command: true) == .move(ids[1], .up))
        #expect(command(.down, .item(ids[1]), command: true) == .move(ids[1], .down))
        #expect(command(.up, .item(ids[0]), command: true) == nil)
        #expect(command(.down, .item(ids[2]), command: true) == nil)
        #expect(command(.up, .newRow, command: true) == nil)
    }

    @Test func commandDeleteDeletesTheSelectedRow() {
        #expect(command(.deleteBackward, .item(ids[0]), command: true) == .delete(ids[0]))
        #expect(command(.deleteBackward, .item(ids[0])) == nil)       // plain ⌫ never deletes a whole to-do
        #expect(command(.deleteBackward, .newRow, command: true) == nil)
    }

    @Test func commandWithOtherKeysIsNotOurs() {
        #expect(command(.space, .item(ids[0]), command: true) == nil)
        #expect(command(.returnKey, .item(ids[0]), command: true) == nil)
    }

    @Test func aSelectionThatIsGoneStartsOver() {
        #expect(command(.down, .item(UUID())) == .select(.item(ids[0])))
    }

    @Test func selectionMovesToTheNextSurvivorWhenItsRowDisappears() {
        let (a, b, c) = (ids[0], ids[1], ids[2])
        #expect(TodoKeyMap.selection(replacing: b, oldVisible: [a, b, c], newVisible: [a, c]) == .item(c))
        #expect(TodoKeyMap.selection(replacing: c, oldVisible: [a, b, c], newVisible: [a, b]) == .item(b))
        #expect(TodoKeyMap.selection(replacing: a, oldVisible: [a], newVisible: []) == .newRow)
        #expect(TodoKeyMap.selection(replacing: UUID(), oldVisible: [a], newVisible: [a]) == .item(a))
    }

    @Test func editorCommandsComeFromKeyBindingSelectors() {
        #expect(TodoEditorCommand(selector: #selector(NSResponder.insertNewline(_:))) == .commit)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.cancelOperation(_:))) == .cancel)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.deleteBackward(_:))) == .deleteBackward)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.moveUp(_:))) == .previous)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.moveDown(_:))) == .next)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.moveToBeginningOfDocument(_:))) == .moveUp)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.moveToEndOfDocument(_:))) == .moveDown)
        #expect(TodoEditorCommand(selector: #selector(NSResponder.insertTab(_:))) == nil)       // Tab moves on
        #expect(TodoEditorCommand(selector: #selector(NSResponder.moveLeft(_:))) == nil)
    }

    @Test func standardKeyBindingsMapCommandArrowsToDocumentMoves() throws {
        // ⌘↑ / ⌘↓ reach the field editor as these selectors (macOS default key bindings).
        let url = URL(fileURLWithPath: "/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict")
        let bindings = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        #expect(bindings["@\u{F700}"] as? String == "moveToBeginningOfDocument:")
        #expect(bindings["@\u{F701}"] as? String == "moveToEndOfDocument:")
    }
}
