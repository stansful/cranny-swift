// CrannyOnboarding/Model/ShortcutText.swift — the key caps onboarding shows (pure): the person's own
// Open Cranny binding, and the six keys of step 6's cheat sheet.
import CrannyCore
import Foundation

nonisolated enum ShortcutText {
    /// The Open Cranny combo as stored in `CoreSettings.shortcuts`: the override, the default ⌃⌥N when there
    /// is none, or nil when the person turned it off.
    static func openCranny(_ overrides: [ShortcutID: KeyCombo?]) -> String? {
        if let entry = overrides[.openNook] { return entry?.display }
        return KeyCombo.openNookDefault.display
    }
}

/// One line of step 6's cheat sheet.
nonisolated struct CheatSheetEntry: Identifiable, Equatable, Sendable {
    enum Action: String, CaseIterable, Sendable { case open, hints, palette, pin, edit, close }
    let action: Action
    /// Key cap text ("⌘K"); "⌘" for the hold-⌘ hints.
    let keys: String
    var id: Action { action }

    /// Six keys (DESIGN.md §12.1, keyboard map §16), starting with the person's Open Cranny binding.
    static func sheet(openCranny: String?) -> [CheatSheetEntry] {
        var entries = [
            CheatSheetEntry(action: .hints, keys: "⌘"),
            CheatSheetEntry(action: .palette, keys: "⌘K"),
            CheatSheetEntry(action: .pin, keys: "⌘P"),
            CheatSheetEntry(action: .edit, keys: "⌘E"),
            CheatSheetEntry(action: .close, keys: "esc"),
        ]
        if let openCranny { entries.insert(CheatSheetEntry(action: .open, keys: openCranny), at: 0) }
        return entries
    }
}
