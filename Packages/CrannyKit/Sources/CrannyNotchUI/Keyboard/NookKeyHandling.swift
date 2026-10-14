// CrannyNotchUI/Keyboard/NookKeyHandling.swift — the open panel's keyboard map (DESIGN.md §16, ARCHITECTURE.md
// §4.10): ⌘K palette · ⌘P pin · ⌘E edit layout · ⌘, Settings · ⌘1–⌘5 pages · ⌃Tab / ⌃⇧Tab next/previous page ·
// Esc steps back (palette, edit layout, focus mode → grid, then close). The table is pure and unit-tested;
// `NookHiddenShortcuts` binds ALL of it once, for as long as the panel is open (works while the panel is key),
// and the visible tabs and buttons only show it as hold-⌘ hints. So a shortcut never disappears with the
// control that shows it (the edit bar replaces the actions; a HUD takes the whole header row).
import CrannyCore
import SwiftUI

/// Something a key does in the open panel.
nonisolated enum NookCommand: Equatable, Sendable {
    case togglePalette
    case togglePin
    case toggleEditLayout
    case openSettings
    /// ⌘1–⌘5: the page at this index of the header's tabs.
    case selectPage(Int)
    case nextPage
    case previousPage
    case escape
}

/// One shortcut of the keyboard map.
nonisolated struct NookShortcut: Equatable, Sendable {
    let command: NookCommand
    let key: Character
    let modifiers: ModifierSet
    /// Key-cap text for hold-⌘ hints ("⌘K").
    let display: String

    /// `EventModifiers` is not `Sendable`/`Equatable`-friendly across isolation; keep our own small set.
    struct ModifierSet: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let command = ModifierSet(rawValue: 1 << 0)
        static let control = ModifierSet(rawValue: 1 << 1)
        static let shift = ModifierSet(rawValue: 1 << 2)
        static let option = ModifierSet(rawValue: 1 << 3)
    }
}

nonisolated enum NookKeyMap {
    /// Pages reachable with ⌘1–⌘5.
    static let numberedPages = 5

    static let palette = NookShortcut(command: .togglePalette, key: "k", modifiers: .command, display: "⌘K")
    static let pin = NookShortcut(command: .togglePin, key: "p", modifiers: .command, display: "⌘P")
    static let editLayout = NookShortcut(command: .toggleEditLayout, key: "e", modifiers: .command, display: "⌘E")
    static let settings = NookShortcut(command: .openSettings, key: ",", modifiers: .command, display: "⌘,")
    static let nextPage = NookShortcut(command: .nextPage, key: "\t", modifiers: .control, display: "⌃⇥")
    static let previousPage = NookShortcut(command: .previousPage, key: "\t", modifiers: [.control, .shift], display: "⌃⇧⇥")

    /// ⌘1 … ⌘5 for the tab at `index` (nil beyond the fifth tab).
    static func page(_ index: Int) -> NookShortcut? {
        guard (0..<numberedPages).contains(index), let key = Character(String(index + 1)).asciiValue.map({ Character(UnicodeScalar($0)) })
        else { return nil }
        return NookShortcut(command: .selectPage(index), key: key, modifiers: .command, display: "⌘\(index + 1)")
    }

    /// Every shortcut of the map (DESIGN.md §16 "In the Nook").
    static var all: [NookShortcut] {
        [palette, pin, editLayout, settings, nextPage, previousPage] + (0..<numberedPages).compactMap(page)
    }

    /// Esc steps back one level: palette, edit layout and focus mode return to the grid; the grid closes.
    static func escape(from mode: NookMode) -> NookMode? {
        mode == .grid ? nil : .grid
    }

    /// The page after (or before) `current` among `pages`, wrapping around; nil with fewer than two pages.
    static func page(after current: PageID, in pages: [PageID], forward: Bool) -> PageID? {
        guard pages.count > 1 else { return nil }
        let index = pages.firstIndex(of: current) ?? 0
        let next = (index + (forward ? 1 : -1) + pages.count) % pages.count
        return pages[next]
    }
}

extension NookShortcut.ModifierSet {
    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if contains(.command) { m.insert(.command) }
        if contains(.control) { m.insert(.control) }
        if contains(.shift) { m.insert(.shift) }
        if contains(.option) { m.insert(.option) }
        return m
    }
}

/// Invisible buttons for the whole keyboard map (`NookKeyMap.all`: ⌘K, ⌘P, ⌘E, ⌘,, ⌘1–⌘5, ⌃Tab, ⌃⇧Tab) and
/// Esc. They draw nothing and take no space; `.keyboardShortcut` makes them key equivalents of the panel while
/// it is key. They live as long as the open panel, whatever the header shows.
struct NookHiddenShortcuts: View {
    let perform: @MainActor (NookCommand) -> Void

    /// Every shortcut bound here (the map plus Esc).
    static var bound: [NookShortcut] { NookKeyMap.all }

    var body: some View {
        ZStack {
            ForEach(Array(Self.bound.enumerated()), id: \.offset) { _, shortcut in
                Button { perform(shortcut.command) } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.modifiers.eventModifiers)
            }
            Button { perform(.escape) } label: { EmptyView() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
