import Foundation
import Testing
@testable import CrannyTodos

/// Ordering and every edit of the pure list (ARCHITECTURE.md §10.7 "store tests: ordering").
struct TodoListTests {
    private func todos(_ titles: String...) -> [Todo] { titles.map { Todo(title: $0) } }
    private func titles(_ list: TodoList) -> [String] { list.items.map(\.title) }

    @Test func insertAppendsWithoutAnchorAndPlacesAfterAnchor() {
        var list = TodoList(todos("a", "b"))
        list.insert(Todo(title: "c"), after: nil)
        #expect(titles(list) == ["a", "b", "c"])
        list.insert(Todo(title: "a2"), after: list.items[0].id)
        #expect(titles(list) == ["a", "a2", "b", "c"])
    }

    @Test func insertAfterAMissingAnchorAppends() {
        var list = TodoList(todos("a"))
        let index = list.insert(Todo(title: "b"), after: UUID())
        #expect(index == 1)
        #expect(titles(list) == ["a", "b"])
    }

    @Test func removeAndRestoreRoundTrip() throws {
        var list = TodoList(todos("a", "b", "c"))
        let original = list
        let removed = list.remove(list.items[1].id)
        let removal = try #require(removed)
        #expect(removal.index == 1)
        #expect(titles(list) == ["a", "c"])
        list.restore([removal])
        #expect(list == original)
        let missing = list.remove(UUID())
        #expect(missing == nil)
    }

    @Test func restoreTwiceDoesNotDuplicate() throws {
        var list = TodoList(todos("a", "b"))
        let removed = list.remove(list.items[0].id)
        let removal = try #require(removed)
        list.restore([removal])
        list.restore([removal])
        #expect(titles(list) == ["a", "b"])
    }

    @Test func removeCompletedKeepsOrderAndRestoresExactly() {
        var list = TodoList(todos("a", "b", "c", "d", "e"))
        let original = list.items.map(\.id)
        for i in [0, 2, 3] { list.setDone(true, for: original[i], at: .now) }
        let snapshot = list
        let removals = list.removeCompleted()
        #expect(titles(list) == ["b", "e"])
        #expect(removals.map(\.index) == [0, 2, 3])
        list.restore(removals)
        #expect(list == snapshot)
    }

    @Test func setDoneStampsAndClearsTheCompletionDate() {
        var list = TodoList(todos("a"))
        let id = list.items[0].id
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let checked = list.setDone(true, for: id, at: date)
        #expect(checked)
        #expect(list.items[0].isDone && list.items[0].completed == date)
        let again = list.setDone(true, for: id, at: .now)
        #expect(!again)                                          // unchanged
        let unchecked = list.setDone(false, for: id, at: .now)
        #expect(unchecked)
        #expect(!list.items[0].isDone && list.items[0].completed == nil)
    }

    @Test func titlesAreOneLine() {
        var list = TodoList(todos("a"))
        list.setTitle("buy\nmilk\tand\r\nbread", for: list.items[0].id)
        #expect(list.items[0].title == "buy milk and bread")      // "\r\n" is one Character
        #expect(TodoList.trimmed("  call mum \n") == "call mum")
    }

    @Test func moveSwapsWithVisibleNeighboursOnly() {
        // a, [h hidden], b, c — moving b up skips nothing visible in between but jumps over h.
        var list = TodoList(todos("a", "h", "b", "c"))
        let ids = list.items.map(\.id)
        let visible: Set = [ids[0], ids[2], ids[3]]
        var moved = list.move(ids[2], .up, visible: visible)
        #expect(moved && titles(list) == ["b", "a", "h", "c"])
        moved = list.move(ids[0], .down, visible: visible)       // a jumps over h to after c
        #expect(moved && titles(list) == ["b", "h", "c", "a"])
        moved = list.move(ids[0], .down, visible: visible)       // a is last among the visible
        #expect(!moved)
        moved = list.move(ids[2], .up, visible: visible)         // b is first
        #expect(!moved)
        moved = list.move(UUID(), .up, visible: visible)
        #expect(!moved)
    }

    @Test func moveDownLandsRightAfterTheNeighbour() {
        var list = TodoList(todos("a", "b", "c"))
        let ids = list.items.map(\.id)
        let moved = list.move(ids[0], .down, visible: Set(ids))
        #expect(moved && titles(list) == ["b", "a", "c"])
    }

    @Test func visibleHidesCompletedUnlessLingeringOrShown() {
        var list = TodoList(todos("a", "b", "c"))
        let ids = list.items.map(\.id)
        list.setDone(true, for: ids[0], at: .now)
        list.setDone(true, for: ids[2], at: .now)
        #expect(list.visible(hidesCompleted: true, lingering: []).map(\.title) == ["b"])
        #expect(list.visible(hidesCompleted: true, lingering: [ids[2]]).map(\.title) == ["b", "c"])
        #expect(list.visible(hidesCompleted: false, lingering: []).map(\.title) == ["a", "b", "c"])
    }

    @Test func countsIgnoreBlankDrafts() {
        var list = TodoList(todos("a", " ", "c"))
        list.setDone(true, for: list.items[2].id, at: .now)
        #expect(list.remainingCount == 1)
        #expect(list.completedCount == 1)
        list.removeBlank()
        #expect(titles(list) == ["a", "c"])
    }

    @Test func neighbourNavigation() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(TodoList.neighbor(of: ids[1], .up, in: ids) == ids[0])
        #expect(TodoList.neighbor(of: ids[1], .down, in: ids) == ids[2])
        #expect(TodoList.neighbor(of: ids[0], .up, in: ids) == nil)
        #expect(TodoList.neighbor(of: ids[2], .down, in: ids) == nil)
        #expect(TodoList.neighbor(of: UUID(), .down, in: ids) == nil)
    }

    @Test func blankMeansWhitespaceOnly() {
        #expect("".isBlank && "  \n\t".isBlank)
        #expect(!" a ".isBlank)
    }
}
