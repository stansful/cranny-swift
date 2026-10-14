// CrannyHUD/Keys/MediaKeyEvent.swift — decoding of the aux-control-button events the key tap sees
// (R3 §1.1, ARCHITECTURE.md §7.1). Pure: the tap passes in the raw numbers, tests pass in literals.
//
// `NX_SYSDEFINED` (14), subtype `NX_SUBTYPE_AUX_CONTROL_BUTTONS` (8). `data1`: bits 31–16 = key code
// (`NX_KEYTYPE_*`), bits 15–8 = state (0x0A down, 0x0B up), bit 0 = auto-repeat. Modifiers come from the
// event's flags (CGEventFlags; the device-independent bits equal NSEvent.ModifierFlags').
import Foundation

/// The `NX_KEYTYPE_*` codes of `IOKit/hidsystem/ev_keymap.h` the HUD cares about (tests check the values).
nonisolated enum MediaKey: Int, Sendable, CaseIterable {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case play = 16, next = 17, previous = 18, fast = 19, rewind = 20
    case illuminationUp = 21, illuminationDown = 22, illuminationToggle = 23
}

/// Device-independent modifier bits (`CGEventFlags.mask…` raw values).
nonisolated struct MediaKeyModifiers: OptionSet, Sendable, Hashable {
    let rawValue: UInt64
    init(rawValue: UInt64) { self.rawValue = rawValue }

    static let shift = MediaKeyModifiers(rawValue: 0x0002_0000)     // CGEventFlags.maskShift
    static let control = MediaKeyModifiers(rawValue: 0x0004_0000)   // .maskControl
    static let option = MediaKeyModifiers(rawValue: 0x0008_0000)    // .maskAlternate
    static let command = MediaKeyModifiers(rawValue: 0x0010_0000)   // .maskCommand

    /// Keeps only the four bits above from an event's flags.
    init(eventFlags: UInt64) {
        self.init(rawValue: eventFlags & (Self.shift.rawValue | Self.control.rawValue | Self.option.rawValue | Self.command.rawValue))
    }
}

/// One decoded media/brightness/illumination key transition.
nonisolated struct MediaKeyEvent: Sendable, Equatable {
    static let systemDefinedType = 14          // NX_SYSDEFINED
    static let auxControlButtonsSubtype = 8    // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    static let keyDownState = 0x0A
    static let keyUpState = 0x0B

    var key: MediaKey
    var isDown: Bool
    var isRepeat: Bool
    var modifiers: MediaKeyModifiers

    init(key: MediaKey, isDown: Bool, isRepeat: Bool = false, modifiers: MediaKeyModifiers = []) {
        self.key = key; self.isDown = isDown; self.isRepeat = isRepeat; self.modifiers = modifiers
    }

    /// ⌥⇧: quarter steps (Apple's convention).
    var isFineStep: Bool { modifiers.contains([.option, .shift]) }
    /// ⌥ without ⇧: macOS opens Sound / Displays / Keyboard settings — always passed through.
    var isOptionOnly: Bool { modifiers.contains(.option) && !modifiers.contains(.shift) }
    /// ⇧ inverts "Play feedback when volume is changed".
    var isShiftHeld: Bool { modifiers.contains(.shift) }

    /// nil for anything that is not an aux-control-button key transition the HUD knows.
    static func decode(subtype: Int, data1: Int, flags: UInt64) -> MediaKeyEvent? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let code = (data1 >> 16) & 0xFFFF
        let keyFlags = data1 & 0xFFFF
        let state = (keyFlags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code), state == keyDownState || state == keyUpState else { return nil }
        return MediaKeyEvent(key: key, isDown: state == keyDownState, isRepeat: keyFlags & 0x1 != 0,
                             modifiers: MediaKeyModifiers(eventFlags: flags))
    }
}
