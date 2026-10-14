// CrannyAppShell/MenuBar/MenuKeyEquivalent.swift — shows a global shortcut (a Carbon `KeyCombo`) as the key
// equivalent of its menu item, so the menu always tells the truth about the user's current binding: "Open
// Cranny ⌃⌥N" by default, the new combination after a rebind, nothing when the shortcut is off or failed.
import AppKit
import Carbon.HIToolbox
import CrannyCore
import SwiftUI

nonisolated enum MenuKeyEquivalent {
    /// The SwiftUI shortcut that draws `combo` in a menu, or nil for a key a menu cannot show.
    static func shortcut(for combo: KeyCombo) -> KeyboardShortcut? {
        guard let key = keyEquivalent(forKeyCode: Int(combo.keyCode)) else { return nil }
        return KeyboardShortcut(key, modifiers: modifiers(combo.modifiers))
    }

    static func modifiers(_ modifiers: KeyCombo.Modifiers) -> SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    /// Virtual key codes are physical positions (ANSI); the menu shows the US character, as `KeyCombo.display` does.
    static func keyEquivalent(forKeyCode code: Int) -> KeyEquivalent? {
        if let character = characters[code] { return KeyEquivalent(character) }
        if let special = specialKeys[code] { return special }
        if let index = functionKeys.firstIndex(of: code), let scalar = UnicodeScalar(NSF1FunctionKey + index) {
            return KeyEquivalent(Character(scalar))
        }
        return nil
    }

    // MARK: Tables

    private static let characters: [Int: Character] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]

    private static let specialKeys: [Int: KeyEquivalent] = [
        kVK_Space: .space, kVK_Return: .return, kVK_Tab: .tab, kVK_Escape: .escape, kVK_Delete: .delete,
        kVK_ForwardDelete: .deleteForward, kVK_Home: .home, kVK_End: .end, kVK_PageUp: .pageUp, kVK_PageDown: .pageDown,
        kVK_LeftArrow: .leftArrow, kVK_RightArrow: .rightArrow, kVK_UpArrow: .upArrow, kVK_DownArrow: .downArrow,
    ]

    /// kVK_F1 … kVK_F20, in order (their codes are not contiguous).
    private static let functionKeys: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
}
