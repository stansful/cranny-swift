// OPT-IN end-to-end check of the acceptance item "no MenuBarAgent OSD window appears" (ARCHITECTURE.md §10.10),
// after R3's verified `reference/e2e`: the real tap consumes a synthetic volume-down and volume-up and applies them
// through CoreAudio; the system's OSD (MenuBarAgent, layer 101) must not appear and the level must come back.
//
// It changes the output volume by one step for about a second and restores it, posts synthetic key events and
// needs Accessibility for the test runner, so it never runs in CI or by default:
//   CRANNY_INTEGRATION=1 CRANNY_HUD_KEYS=1 swift test --scratch-path .build-test --filter HUDKeyIntegrationTests
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hidsystem
import Testing
@testable import CrannyHUD

private nonisolated let enabled = ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"
    && ProcessInfo.processInfo.environment["CRANNY_HUD_KEYS"] == "1"

@MainActor @Suite(.serialized, .enabled(if: enabled, "changes the volume and posts keys; opt-in only"))
struct HUDKeyIntegrationTests {
    /// Posts one aux-control key (down, then up) at the HID level, as the keyboard would.
    private func press(_ key: Int32) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)), timestamp: 0,
                                           windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                                           data1: (Int(key) << 16) | flags, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// The macOS 27 volume OSD: a MenuBarAgent window at layer 101 (R3 §1.2).
    private func osdWindowCount() -> Int {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        return windows.filter {
            ($0[kCGWindowOwnerName as String] as? String) == "MenuBarAgent" && ($0[kCGWindowLayer as String] as? Int) == 101
        }.count
    }

    @Test func consumedVolumeKeysChangeTheLevelWithoutTheSystemOSD() async throws {
        try #require(AXIsProcessTrusted(), "grant Accessibility to the process running the tests")
        let volume = CoreAudioVolume()
        let before = try #require(volume.readState(), "the default output has no settable volume")
        let config = HUDTapConfigBox()
        config.update(HUDTapConfig(isReplacing: true, handlesVolume: true, handlesBrightness: false,
                                   handlesKeyboardBacklight: false, isPresentable: true))
        let recorder = SignalRecorder()
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: FakeLevel(nil), keyboard: FakeLevel(nil),
                                      sink: recorder.sink)
        let tap = MediaKeyInterceptor(handler: handler)
        try #require(tap.start(), "the event tap could not be created")
        defer {
            tap.stop()
            _ = volume.setLevel(before.level)
            _ = volume.setMuted(before.isMuted)
        }
        try await Task.sleep(for: .milliseconds(300))
        let osdBefore = osdWindowCount()

        press(NX_KEYTYPE_SOUND_DOWN)
        try await Task.sleep(for: .milliseconds(500))
        let down = try #require(volume.readState())
        #expect(down.level == LevelStepper.step(before.level, up: false, fine: false))
        #expect(osdWindowCount() == osdBefore, "the system OSD appeared: the key was not consumed")

        press(NX_KEYTYPE_SOUND_UP)
        try await Task.sleep(for: .milliseconds(500))
        #expect(osdWindowCount() == osdBefore)
        #expect(recorder.updates.count == 2)
        #expect(recorder.signals.filter { if case .volumeKeyReleased = $0 { true } else { false } }.count == 2)
    }
}
