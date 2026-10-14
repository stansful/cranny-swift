// CrannyNotes/Editor/NoteKeyCommand.swift — the editor's ⌘ shortcuts (DESIGN.md §16 keyboard map): ⌘N new · ⌘R
// rename · ⌘[ / ⌘] previous/next note · ⌘↩ focus · ⌘/ code mode, plus ⌘A/C/X/V/Z/⇧⌘Z handled by the editor itself
// so they work in the non-activating panel whatever the menu bar does. Matched by character on Latin layouts and
// by physical key otherwise (⌘C on a Russian layout reports "с").
import AppKit

nonisolated enum NoteKeyCommand: Equatable, Sendable {
    case newNote, rename, previousNote, nextNote, toggleFocus, toggleCodeMode
    case selectAll, copy, cut, paste, undo, redo

    /// kVK_* virtual key codes (Carbon HIToolbox/Events.h) for layout-independent matching.
    private enum Key {
        static let a: UInt16 = 0, z: UInt16 = 6, x: UInt16 = 7, c: UInt16 = 8, v: UInt16 = 9, r: UInt16 = 15
        static let rightBracket: UInt16 = 30, leftBracket: UInt16 = 33, `return`: UInt16 = 36, n: UInt16 = 45
        static let slash: UInt16 = 44, keypadEnter: UInt16 = 76
    }

    /// `characters` = `charactersIgnoringModifiers`. Only ⌘ (and ⇧ for redo) combinations match.
    init?(characters: String, keyCode: UInt16, command: Bool, shift: Bool, option: Bool, control: Bool) {
        guard command, !option, !control else { return nil }
        if keyCode == Key.return || keyCode == Key.keypadEnter {
            guard !shift else { return nil }
            self = .toggleFocus
            return
        }
        let latin = characters.count == 1 && characters.unicodeScalars.allSatisfy(\.isASCII)
        let key = latin ? characters.lowercased() : Self.character(forKeyCode: keyCode)
        switch (key, shift) {
        case ("n", false): self = .newNote
        case ("r", false): self = .rename
        case ("[", false): self = .previousNote
        case ("]", false): self = .nextNote
        case ("/", false): self = .toggleCodeMode
        case ("a", false): self = .selectAll
        case ("c", false): self = .copy
        case ("x", false): self = .cut
        case ("v", false): self = .paste
        case ("z", false): self = .undo
        case ("z", true): self = .redo
        default: return nil                                               // ⇧⌘[ / ⇧⌘] stay the system's tab switch
        }
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(characters: event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode,
                  command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }

    private static func character(forKeyCode code: UInt16) -> String {
        switch code {
        case Key.a: "a"
        case Key.z: "z"
        case Key.x: "x"
        case Key.c: "c"
        case Key.v: "v"
        case Key.r: "r"
        case Key.n: "n"
        case Key.leftBracket: "["
        case Key.rightBracket: "]"
        case Key.slash: "/"
        default: ""
        }
    }

    /// Commands the editor performs itself; the others go to the model.
    var isTextCommand: Bool {
        switch self {
        case .selectAll, .copy, .cut, .paste, .undo, .redo: true
        default: false
        }
    }
}
