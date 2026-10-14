// `data1` decoding (key, down/up, repeat, ⌥, ⌥⇧) and the tap's event classification (ARCHITECTURE.md §10.10).
import CoreGraphics
import IOKit.hidsystem
import Testing
@testable import CrannyHUD

/// `data1` as macOS builds it: key code in bits 31–16, state in 15–8, repeat in bit 0.
private func data1(_ key: Int32, down: Bool, repeat isRepeat: Bool = false) -> Int {
    (Int(key) << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
}

@Suite struct MediaKeyEventTests {
    @Test func keyCodesMatchTheSDK() {
        #expect(MediaKey.soundUp.rawValue == Int(NX_KEYTYPE_SOUND_UP))
        #expect(MediaKey.soundDown.rawValue == Int(NX_KEYTYPE_SOUND_DOWN))
        #expect(MediaKey.brightnessUp.rawValue == Int(NX_KEYTYPE_BRIGHTNESS_UP))
        #expect(MediaKey.brightnessDown.rawValue == Int(NX_KEYTYPE_BRIGHTNESS_DOWN))
        #expect(MediaKey.mute.rawValue == Int(NX_KEYTYPE_MUTE))
        #expect(MediaKey.play.rawValue == Int(NX_KEYTYPE_PLAY))
        #expect(MediaKey.next.rawValue == Int(NX_KEYTYPE_NEXT))
        #expect(MediaKey.previous.rawValue == Int(NX_KEYTYPE_PREVIOUS))
        #expect(MediaKey.fast.rawValue == Int(NX_KEYTYPE_FAST))
        #expect(MediaKey.rewind.rawValue == Int(NX_KEYTYPE_REWIND))
        #expect(MediaKey.illuminationUp.rawValue == Int(NX_KEYTYPE_ILLUMINATION_UP))
        #expect(MediaKey.illuminationDown.rawValue == Int(NX_KEYTYPE_ILLUMINATION_DOWN))
        #expect(MediaKey.illuminationToggle.rawValue == Int(NX_KEYTYPE_ILLUMINATION_TOGGLE))
        #expect(MediaKeyEvent.systemDefinedType == Int(NX_SYSDEFINED))
        #expect(MediaKeyEvent.auxControlButtonsSubtype == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS))
    }

    @Test func modifierBitsMatchCGEventFlags() {
        #expect(MediaKeyModifiers.shift.rawValue == CGEventFlags.maskShift.rawValue)
        #expect(MediaKeyModifiers.control.rawValue == CGEventFlags.maskControl.rawValue)
        #expect(MediaKeyModifiers.option.rawValue == CGEventFlags.maskAlternate.rawValue)
        #expect(MediaKeyModifiers.command.rawValue == CGEventFlags.maskCommand.rawValue)
    }

    @Test func decodesKeyDownAndUp() throws {
        let down = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: 0))
        #expect(down == MediaKeyEvent(key: .soundUp, isDown: true))
        let up = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: false), flags: 0))
        #expect(up == MediaKeyEvent(key: .soundUp, isDown: false))
        let mute = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_MUTE, down: true), flags: 0))
        #expect(mute.key == .mute)
        let brightness = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_BRIGHTNESS_DOWN, down: true), flags: 0))
        #expect(brightness.key == .brightnessDown)
    }

    @Test func decodesRepeat() throws {
        let held = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_DOWN, down: true, repeat: true), flags: 0))
        #expect(held.isRepeat)
        #expect(held.isDown)
        let first = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_DOWN, down: true), flags: 0))
        #expect(!first.isRepeat)
    }

    @Test func decodesModifiers() throws {
        let option = CGEventFlags.maskAlternate.rawValue
        let shift = CGEventFlags.maskShift.rawValue
        let optionOnly = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: option))
        #expect(optionOnly.isOptionOnly)
        #expect(!optionOnly.isFineStep)
        let fine = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: option | shift))
        #expect(fine.isFineStep)
        #expect(!fine.isOptionOnly)
        #expect(fine.isShiftHeld)
        let shiftOnly = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: shift))
        #expect(shiftOnly.isShiftHeld)
        #expect(!shiftOnly.isFineStep)
        #expect(!shiftOnly.isOptionOnly)
        // Caps Lock, Fn and device-dependent bits are dropped.
        let noisy = CGEventFlags.maskAlphaShift.rawValue | CGEventFlags.maskSecondaryFn.rawValue | 0x0000_0108
        let plain = try #require(MediaKeyEvent.decode(subtype: 8, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: noisy))
        #expect(plain.modifiers.isEmpty)
    }

    @Test func rejectsWhatIsNotAnAuxKeyTransition() {
        #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(NX_KEYTYPE_SOUND_UP, down: true), flags: 0) == nil)
        #expect(MediaKeyEvent.decode(subtype: 8, data1: (5 << 16) | 0x0A00, flags: 0) == nil)          // unknown key
        #expect(MediaKeyEvent.decode(subtype: 8, data1: (0 << 16) | 0x0C00, flags: 0) == nil)          // unknown state
        #expect(MediaKeyEvent.decode(subtype: 8, data1: 0, flags: 0) == nil)
    }

    @Test func classifiesTapEvents() {
        #expect(TapEventKind(rawType: CGEventType.tapDisabledByTimeout.rawValue) == .reenable)
        #expect(TapEventKind(rawType: CGEventType.tapDisabledByUserInput.rawValue) == .reenable)
        #expect(TapEventKind(rawType: UInt32(NX_SYSDEFINED)) == .systemDefined)
        #expect(TapEventKind(rawType: CGEventType.keyDown.rawValue) == .other)
    }
}
