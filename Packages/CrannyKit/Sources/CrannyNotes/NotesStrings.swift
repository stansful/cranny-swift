// CrannyNotes/NotesStrings.swift — every user-visible string of the module, in one place so each key has exactly
// one translator comment ("<Surface>: <purpose>", ARCHITECTURE.md §10.0). Always looked up in `Bundle.module`.
import CrannyCore
import Foundation

nonisolated enum NotesStrings {
    // MARK: Module

    static var notes: String {
        String(localized: "Notes", bundle: .module, comment: "Notes: module name (widget title, type-to-capture target, ⌘K result kind)")
    }
    static var summary: String {
        String(localized: "Quick notes with code highlighting", bundle: .module, comment: "Widget library: Notes description")
    }
    static var newNote: String {
        String(localized: "New note", bundle: .module, comment: "Notes: create a note (button, menu item, ⌘K command, shortcut name)")
    }
    static func open(_ title: String) -> String {
        String(localized: "Open “\(title)”", bundle: .module, comment: "Command palette: open a note; the argument is its title")
    }

    // MARK: Titles

    static var untitled: String {
        String(localized: "Untitled", bundle: .module, comment: "Notes: title of a new note")
    }
    static func untitled(_ number: Int) -> String {
        String(localized: "Untitled \(number)", bundle: .module, comment: "Notes: title of a new note when “Untitled” is taken; the argument is a number")
    }
    static var noteTitle: String {
        String(localized: "Note title", bundle: .module, comment: "Notes widget: the title (VoiceOver label, rename field placeholder)")
    }
    static var doubleClickToRename: String {
        String(localized: "Double-click to rename", bundle: .module, comment: "Notes widget: tooltip on the title")
    }

    // MARK: States

    static var empty: String {
        String(localized: "No notes yet", bundle: .module, comment: "Notes widget: empty state")
    }
    static var placeholder: String {
        String(localized: "Start typing", bundle: .module, comment: "Notes widget: placeholder in an empty note")
    }
    static var loadFailed: String {
        String(localized: "Notes couldn’t be loaded", bundle: .module, comment: "Notes widget: error state when the notes folder can’t be read")
    }
    static var saveFailed: String {
        String(localized: "Couldn’t save. Cranny will try again.", bundle: .module, comment: "Notes widget: tooltip and VoiceOver label of the warning shown when saving failed")
    }
    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "Notes widget: retry button in the error state")
    }

    // MARK: Commands

    static var allNotes: String {
        String(localized: "All notes", bundle: .module, comment: "Notes widget: the note list menu button (VoiceOver label, tooltip)")
    }
    static var notesList: String {
        String(localized: "Notes list", bundle: .module, comment: "Notes widget: VoiceOver label of the note list beside the editor (6 cells and wider)")
    }
    static var rename: String {
        String(localized: "Rename", bundle: .module, comment: "Notes: rename the current note (menu item, VoiceOver action)")
    }
    static var deleteEllipsis: String {
        String(localized: "Delete…", bundle: .module, comment: "Notes: menu item that asks before deleting the current note")
    }
    static var previousNote: String {
        String(localized: "Previous note", bundle: .module, comment: "Notes: menu item (⌘[)")
    }
    static var nextNote: String {
        String(localized: "Next note", bundle: .module, comment: "Notes: menu item (⌘])")
    }
    static var codeMode: String {
        String(localized: "Code mode", bundle: .module, comment: "Notes widget: code mode toggle (button tooltip, VoiceOver label)")
    }
    static var focusMode: String {
        String(localized: "Focus", bundle: .module, comment: "Notes widget: button that enlarges the note to the whole panel (tooltip, VoiceOver label)")
    }
    static var exitFocusMode: String {
        String(localized: "Exit focus", bundle: .module, comment: "Notes widget: button that ends focus mode (tooltip, VoiceOver label)")
    }

    // MARK: Delete confirmation

    static func deleteQuestion(_ title: String) -> String {
        String(localized: "Delete “\(title.crannyIsolated)”?", bundle: .module, comment: "Notes widget: delete confirmation; the argument is the note’s title")
    }
    static var deleteDetail: String {
        String(localized: "You can’t undo this.", bundle: .module, comment: "Notes widget: delete confirmation, second line")
    }
    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Notes widget: delete confirmation, keep the note")
    }
    static var delete: String {
        String(localized: "Delete", bundle: .module, comment: "Notes widget: delete confirmation, delete the note")
    }

    // MARK: Mode and language

    static var mode: String {
        String(localized: "Mode", bundle: .module, comment: "Notes: menu section for plain text or code")
    }
    static var plainText: String {
        String(localized: "Plain text", bundle: .module, comment: "Notes: note mode (menu item, options picker)")
    }
    static var code: String {
        String(localized: "Code", bundle: .module, comment: "Notes: note mode with syntax colours (menu item, options picker)")
    }
    static var language: String {
        String(localized: "Language", bundle: .module, comment: "Notes: code mode language submenu")
    }
    static var automatic: String {
        String(localized: "Automatic", bundle: .module, comment: "Notes: code language, detected from the title or the text")
    }
    static func automatic(_ detected: String) -> String {
        String(localized: "Automatic (\(detected))", bundle: .module, comment: "Notes: code language menu item; the argument is the detected language, e.g. Swift")
    }

    // MARK: Options (Layout & Widgets, the card's ⋯ menu)

    static var typingEffect: String {
        String(localized: "Typing effect", bundle: .module, comment: "Widget options: Notes typing effect toggle")
    }
    static var typingEffectFootnote: String {
        String(localized: "New characters appear in the accent color, then settle.", bundle: .module, comment: "Widget options: footnote under the Notes typing effect toggle")
    }
    static var newNotes: String {
        String(localized: "New notes", bundle: .module, comment: "Widget options: label of the picker for the mode of new notes")
    }
}
