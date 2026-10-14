// The open panel's keyboard map (DESIGN.md §16) and the ⌘K palette's ranking and selection (§6.4).
import CrannyCore
import Foundation
import Testing
@testable import CrannyNotchUI

@Suite("Keyboard map (DESIGN.md §16)") struct KeyboardMapTests {
    @Test func everyShortcutOfTheNook() {
        let map = Dictionary(NookKeyMap.all.map { ($0.display, $0.command) }, uniquingKeysWith: { a, _ in a })
        #expect(map["⌘K"] == .togglePalette)
        #expect(map["⌘P"] == .togglePin)
        #expect(map["⌘E"] == .toggleEditLayout)
        #expect(map["⌘,"] == .openSettings)
        #expect(map["⌃⇥"] == .nextPage)
        #expect(map["⌃⇧⇥"] == .previousPage)
        for n in 1...5 { #expect(map["⌘\(n)"] == .selectPage(n - 1)) }
        #expect(NookKeyMap.page(5) == nil)                                    // ⌘1–⌘5 only
        #expect(NookKeyMap.palette.key == "k" && NookKeyMap.palette.modifiers == .command)
        #expect(NookKeyMap.page(2)?.key == "3")
        #expect(NookKeyMap.nextPage.modifiers == .control && NookKeyMap.previousPage.modifiers == [.control, .shift])
        // No two shortcuts share a key equivalent.
        let keys = NookKeyMap.all.map { "\($0.key)\($0.modifiers.rawValue)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test func escapeStepsBackBeforeItCloses() {
        #expect(NookKeyMap.escape(from: .palette) == .grid)
        #expect(NookKeyMap.escape(from: .editLayout) == .grid)
        #expect(NookKeyMap.escape(from: .focus(.notes)) == .grid)
        #expect(NookKeyMap.escape(from: .catchFiles([])) == .grid)
        #expect(NookKeyMap.escape(from: .grid) == nil)                       // nil = close
    }

    @Test func controlTabCyclesThePages() {
        let pages: [PageID] = [.nook, "page.focus", .tray]
        #expect(NookKeyMap.page(after: .nook, in: pages, forward: true) == "page.focus")
        #expect(NookKeyMap.page(after: .tray, in: pages, forward: true) == .nook)
        #expect(NookKeyMap.page(after: .nook, in: pages, forward: false) == .tray)
        #expect(NookKeyMap.page(after: .nook, in: [.nook], forward: true) == nil)
    }
}

@Suite("Command palette (DESIGN.md §6.4)") struct PaletteTests {
    @Test func bestMatchesFirst() {
        let items: [(title: String, keywords: [String])] = [
            ("Clear tray", ["files"]),
            ("Start 25-minute timer", ["pomodoro"]),
            ("New note", []),
            ("Pause live activities for 1 hour", ["silence"]),
            ("Open Notes", []),
        ]
        #expect(PaletteSearch.order(items, query: "") == [0, 1, 2, 3, 4])
        #expect(PaletteSearch.order(items, query: "no") == [2, 4])            // word prefixes, in provider order
        #expect(PaletteSearch.order(items, query: "pomo") == [1])             // keyword prefix
        #expect(PaletteSearch.order(items, query: "TIMER") == [1])            // case-insensitive
        #expect(PaletteSearch.order(items, query: "open").first == 4)         // title prefix wins
        #expect(PaletteSearch.order(items, query: "zzz").isEmpty)
        #expect(PaletteSearch.score(title: "Новая заметка", keywords: [], query: "нов") == 0)
        #expect(PaletteSearch.score(title: "Démo", keywords: [], query: "demo") == 0)   // diacritics ignored
    }

    @Test func selectionScrollsAWindowOfFourRows() {
        var s = PaletteSelection()
        s.move(by: -1, count: 10, visible: 4)
        #expect(s == PaletteSelection(index: 0, firstVisible: 0))
        for _ in 0..<5 { s.move(by: 1, count: 10, visible: 4) }
        #expect(s.index == 5 && s.firstVisible == 2)
        for _ in 0..<20 { s.move(by: 1, count: 10, visible: 4) }
        #expect(s.index == 9 && s.firstVisible == 6)
        s.clamp(count: 3, visible: 4)
        #expect(s.index == 2 && s.firstVisible == 0)
        s.move(by: 1, count: 0, visible: 4)
        #expect(s == PaletteSelection())
    }

    @Test func rowsFitTheGridArea() {
        #expect(PaletteSelection.visibleRows(height: 120) == 4)               // Standard: 28 + 4 + 4 × 22
        #expect(PaletteSelection.visibleRows(height: 110) == 3)               // Compact density
        #expect(PaletteSelection.visibleRows(height: 200) == 4)               // never more than 4
        #expect(PaletteSelection.visibleRows(height: 20) == 1)
    }
}
