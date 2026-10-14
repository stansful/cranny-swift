// CrannySettingsUI/Panes/KeyComboFormatter.swift — turning a recorded key press into a `KeyCombo` and its key-cap text
// ("⌃⌥N"): modifiers in Apple's order ⌃ ⌥ ⇧ ⌘, named keys as symbols, letters from the current ASCII-capable keyboard
// layout (so a Russian layout still shows "N", as macOS menus do). The rules of what may be a global shortcut are
// pure and tested: it needs ⌘, ⌃ or ⌥ (⇧ alone is typing), except for function keys.
import AppKit
import Carbon
import CrannyCore
import Foundation

enum KeyComboFormatter {
    /// What a key press means to the recorder.
    enum Outcome: Equatable {
        case combo(KeyCombo)
        case cancel          // Esc without modifiers
        case clear           // Delete or Forward Delete without modifiers: turn the shortcut off
        case needsModifier   // a plain or ⇧-only key that is not a function key
    }

    /// The recorder's decision for `keyCode` with `modifiers`; `character` is the layout's character for the key.
    static func outcome(keyCode: UInt16, modifiers: KeyCombo.Modifiers, character: String?) -> Outcome {
        let hasCommandKey = !modifiers.intersection([.command, .control, .option]).isEmpty
        if !hasCommandKey && modifiers.isEmpty {
            if keyCode == UInt16(kVK_Escape) { return .cancel }
            if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) { return .clear }
        }
        if !hasCommandKey && !functionKeys.keys.contains(keyCode) { return .needsModifier }
        return .combo(KeyCombo(keyCode: keyCode, modifiers: modifiers, display: display(keyCode: keyCode, modifiers: modifiers, character: character)))
    }

    /// "⌃⌥⇧⌘" + the key's name.
    static func display(keyCode: UInt16, modifiers: KeyCombo.Modifiers, character: String?) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyName(keyCode: keyCode, character: character)
    }

    static func keyName(keyCode: UInt16, character: String?) -> String {
        if let name = functionKeys[keyCode] ?? namedKeys[keyCode] { return name }
        if keyCode == UInt16(kVK_Space) {
            return String(localized: "Space", bundle: .module, comment: "Settings ▸ Keyboard: name of the space bar in a shortcut")
        }
        let trimmed = (character ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "#\(keyCode)" : trimmed
    }

    /// `NSEvent.ModifierFlags` → `KeyCombo.Modifiers` (Caps Lock and Fn ignored).
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    /// The character `keyCode` types on the current ASCII-capable layout (no modifiers), e.g. "n".
    @MainActor static func layoutCharacter(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    // MARK: Key tables (Carbon virtual key codes, HIToolbox/Events.h)

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static let namedKeys: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}
