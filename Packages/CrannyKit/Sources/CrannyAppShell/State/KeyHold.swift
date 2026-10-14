// CrannyAppShell/State/KeyHold.swift — whether the panel's key status holds it open: the shell's `typing` hold
// (ARCHITECTURE.md §4.5, §4.10). Pure, so tests drive it without windows; `FocusManager` feeds it the key-window
// notifications, its own key requests and first-responder changes, and sends the hold when it flips.
//
// Key status taken for typing (the hot key, a clicked text view, `requestKeyboardFocus()`) holds the panel open, as
// before. Key status taken for a selection (`NotchSelectionFocus.requestSelectionFocus()`, a Tray tile click) does
// not: the panel still closes when the pointer leaves, and the close hands key status back. It becomes a typing hold
// once a text view or field editor becomes first responder or a typing request arrives; nothing ever downgrades it.
import Foundation

nonisolated struct KeyHold: Equatable, Sendable {
    /// The panel is key.
    private(set) var isKey = false
    /// The `typing` hold is on.
    private(set) var holdsOpen = false
    /// A selection asked for key status and the panel has not become key yet.
    private var selectionPending = false

    /// A request for key status: `forTyping` false for a selection. While the panel is already key, a typing request
    /// turns the hold on and a selection request changes nothing.
    mutating func request(forTyping: Bool) {
        if isKey {
            if forTyping { holdsOpen = true }
        } else {
            selectionPending = !forTyping
        }
    }

    /// The request returned. The key-window notification arrives during `makeKey()`; one that comes later (a text
    /// view clicked afterwards) is typing again.
    mutating func requestEnded() { selectionPending = false }

    mutating func becameKey() {
        if !isKey {
            isKey = true
            holdsOpen = !selectionPending
        }
        selectionPending = false
    }

    mutating func resignedKey() {
        isKey = false
        holdsOpen = false
        selectionPending = false
    }

    /// A text view or a field editor became first responder: typing holds the panel open.
    mutating func editingBegan() {
        if isKey { holdsOpen = true }
    }
}
