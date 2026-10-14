// Consume vs pass through with devices (fakes only), key-up symmetry, mute, ends and fine steps.
import Testing
@testable import CrannyHUD

@Suite struct MediaKeyHandlerTests {
    let config = HUDTapConfigBox()
    let volume = FakeVolume()
    let brightness = FakeLevel(0.5)
    let keyboard = FakeLevel(0.5)
    let recorder = SignalRecorder()

    init() { config.update(.all) }

    private var handler: MediaKeyHandler {
        MediaKeyHandler(config: config, volume: volume, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
    }

    private func down(_ key: MediaKey, _ modifiers: MediaKeyModifiers = [], repeat isRepeat: Bool = false) -> MediaKeyEvent {
        MediaKeyEvent(key: key, isDown: true, isRepeat: isRepeat, modifiers: modifiers)
    }
    private func up(_ key: MediaKey, _ modifiers: MediaKeyModifiers = []) -> MediaKeyEvent {
        MediaKeyEvent(key: key, isDown: false, modifiers: modifiers)
    }

    @Test func consumesVolumeUpAppliesOneStepAndReportsIt() throws {
        let handler = handler
        #expect(handler.handle(down(.soundUp)))
        #expect(volume.state?.level == 0.5625)
        let update = try #require(recorder.updates.first)
        #expect(update.kind == .volume)
        #expect(update.level == 0.5625)
        #expect(update.limit == nil)
        #expect(!update.isFineStep)
        #expect(handler.handle(up(.soundUp)))
        #expect(recorder.signals.last == .volumeKeyReleased(shiftHeld: false))
    }

    @Test func optionShiftMovesAQuarterStep() {
        #expect(handler.handle(down(.soundDown, [.option, .shift])))
        #expect(volume.state?.level == 0.484375)
        #expect(recorder.updates.first?.isFineStep == true)
    }

    @Test func optionAlonePassesBothTransitions() {
        let handler = handler
        #expect(!handler.handle(down(.soundUp, .option)))
        #expect(!handler.handle(up(.soundUp, .option)))
        #expect(volume.calls.isEmpty)
        #expect(recorder.signals.isEmpty)
    }

    @Test func unsettableOutputPassesThrough() {
        let hdmi = FakeVolume(nil)
        let handler = MediaKeyHandler(config: config, volume: hdmi, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(!handler.handle(down(.soundUp)))
        #expect(!handler.handle(up(.soundUp)))
        #expect(recorder.signals.isEmpty)
    }

    @Test func aFailedWritePassesThrough() {
        volume.failWrites()
        #expect(!handler.handle(down(.soundUp)))
        #expect(recorder.signals.isEmpty)
    }

    @Test func pressingPastTheTopIsConsumedWithoutAWrite() {
        let full = FakeVolume(VolumeState(level: 1, isMuted: false, canMute: true))
        let handler = MediaKeyHandler(config: config, volume: full, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(handler.handle(down(.soundUp)))
        #expect(full.calls.isEmpty)
        #expect(recorder.updates.first?.limit == .pressedPast(.top))
    }

    @Test func reachingTheBottomIsReported() {
        let low = FakeVolume(VolumeState(level: 0.0625, isMuted: false, canMute: true))
        let handler = MediaKeyHandler(config: config, volume: low, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(handler.handle(down(.soundDown)))
        #expect(low.state?.level == 0)
        #expect(recorder.updates.first?.limit == .reached(.bottom))
    }

    @Test func volumeUpUnmutes() {
        let muted = FakeVolume(VolumeState(level: 0.25, isMuted: true, canMute: true))
        let handler = MediaKeyHandler(config: config, volume: muted, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(handler.handle(down(.soundUp)))
        #expect(muted.calls == ["muted(false)", "level(0.3125)"])
        #expect(recorder.updates.first?.isMuted == false)
    }

    @Test func volumeDownKeepsMute() {
        let muted = FakeVolume(VolumeState(level: 0.25, isMuted: true, canMute: true))
        let handler = MediaKeyHandler(config: config, volume: muted, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(handler.handle(down(.soundDown)))
        #expect(muted.calls == ["level(0.1875)"])
        #expect(recorder.updates.first?.isMuted == true)
    }

    @Test func muteTogglesOncePerPress() {
        let handler = handler
        #expect(handler.handle(down(.mute)))
        #expect(volume.state?.isMuted == true)
        #expect(handler.handle(down(.mute, repeat: true)))         // held: consumed, no flicker
        #expect(volume.state?.isMuted == true)
        #expect(handler.handle(up(.mute)))
        #expect(handler.handle(down(.mute)))
        #expect(volume.state?.isMuted == false)
        #expect(recorder.updates.map(\.isMuted) == [true, true, false])
        #expect(!recorder.signals.contains(.volumeKeyReleased(shiftHeld: false)))   // no feedback sound for mute
    }

    @Test func muteWithoutAMuteControlPassesThrough() {
        let noMute = FakeVolume(VolumeState(level: 0.5, isMuted: false, canMute: false))
        let handler = MediaKeyHandler(config: config, volume: noMute, brightness: brightness, keyboard: keyboard, sink: recorder.sink)
        #expect(!handler.handle(down(.mute)))
        #expect(noMute.calls.isEmpty)
    }

    @Test func brightnessNeedsAControllableDisplay() {
        let external = FakeLevel(nil)
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: external, keyboard: keyboard, sink: recorder.sink)
        #expect(!handler.handle(down(.brightnessUp)))
        #expect(!handler.handle(up(.brightnessUp)))
        #expect(external.writes.isEmpty)
    }

    @Test func brightnessSteps() throws {
        #expect(handler.handle(down(.brightnessDown)))
        #expect(brightness.level == 0.4375)
        let update = try #require(recorder.updates.first)
        #expect(update.kind == .brightness)
        #expect(update.level == 0.4375)
    }

    @Test func keyboardToggleTurnsOffAndRestores() {
        let handler = handler
        #expect(handler.handle(down(.illuminationToggle)))
        #expect(keyboard.level == 0)
        #expect(handler.handle(down(.illuminationToggle)))
        #expect(keyboard.level == 0.5)
        #expect(handler.handle(down(.illuminationUp)))
        #expect(keyboard.level == 0.5625)
    }

    @Test func keyboardWriteFailurePassesThrough() {
        keyboard.failWrites()
        #expect(!handler.handle(down(.illuminationUp)))
        #expect(!handler.handle(down(.illuminationToggle)))
    }

    @Test func keyUpFollowsItsKeyDownWhateverTheConfig() {
        let handler = handler
        #expect(handler.handle(down(.soundUp)))
        config.update(.off)                                         // the user turned it off mid-press
        #expect(handler.handle(up(.soundUp)))                      // still consumed: macOS never saw the down
        #expect(!handler.handle(down(.soundUp)))
        config.update(.all)                                         // turned on again mid-press
        #expect(!handler.handle(up(.soundUp)))                     // macOS saw the down, so it gets the up
    }

    @Test func transportKeysAreNeverTouched() {
        let handler = handler
        for key in [MediaKey.play, .next, .previous, .fast, .rewind] {
            #expect(!handler.handle(down(key)))
            #expect(!handler.handle(up(key)))
        }
        #expect(recorder.signals.isEmpty)
    }

    @Test func notPresentablePassesThrough() {
        var locked = HUDTapConfig.all
        locked.isPresentable = false
        config.update(locked)
        #expect(!handler.handle(down(.soundUp)))
        #expect(volume.calls.isEmpty)
    }

    @Test func sequencesIncrease() {
        let handler = handler
        _ = handler.handle(down(.soundUp))
        _ = handler.handle(down(.soundUp, repeat: true))
        _ = handler.handle(down(.brightnessUp))
        #expect(recorder.updates.map(\.sequence) == [1, 2, 3])
        #expect(recorder.updates.map(\.isRepeat) == [false, true, false])
    }

    @Test func shiftIsReportedOnRelease() {
        let handler = handler
        _ = handler.handle(down(.soundUp, .shift))
        _ = handler.handle(up(.soundUp, .shift))
        #expect(recorder.signals.last == .volumeKeyReleased(shiftHeld: true))
    }

    @Test func aLateBluetoothReportDoesNotStallAHeldKey() {
        let uptime = FakeUptime()
        volume.reportLate()                                        // the device keeps reading 0.5 for a while
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: brightness, keyboard: keyboard,
                                      uptime: uptime.clock, sink: recorder.sink)
        #expect(handler.handle(down(.soundUp)))
        uptime.advance(0.03)                                       // key repeat
        #expect(handler.handle(down(.soundUp, repeat: true)))
        uptime.advance(0.03)
        #expect(handler.handle(down(.soundUp, repeat: true)))
        #expect(volume.calls == ["level(0.5625)", "level(0.625)", "level(0.6875)"])
        #expect(recorder.updates.map(\.level) == [0.5625, 0.625, 0.6875])
        uptime.advance(MediaKeyHandler.recentVolumeWindow + 0.01)  // later, the device's own report counts again
        #expect(handler.handle(down(.soundUp)))
        #expect(volume.calls.last == "level(0.5625)")
    }

    @Test func aQuickSecondMuteTogglesBackOnALateDevice() {
        let uptime = FakeUptime()
        volume.reportLate()
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: brightness, keyboard: keyboard,
                                      uptime: uptime.clock, sink: recorder.sink)
        _ = handler.handle(down(.mute))
        _ = handler.handle(up(.mute))
        uptime.advance(0.2)
        _ = handler.handle(down(.mute))
        #expect(volume.calls == ["muted(true)", "muted(false)"])
        #expect(recorder.updates.map(\.isMuted) == [true, false])
    }

    @Test func aHeldKeyReadsOnlyTheDevice() {
        let uptime = FakeUptime()
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: brightness, keyboard: keyboard,
                                      uptime: uptime.clock, sink: recorder.sink)
        #expect(handler.handle(down(.soundUp)))
        uptime.advance(0.03)                                       // key repeat
        #expect(handler.handle(down(.soundUp, repeat: true)))
        uptime.advance(0.03)
        #expect(handler.handle(down(.mute)))
        // The repeat and the quick mute step from what Cranny applied: no level or mute read for them.
        #expect(volume.reads == [true, false, false])
        #expect(recorder.updates.map(\.level) == [0.5625, 0.625, 0.625])
        #expect(volume.state == VolumeState(level: 0.625, isMuted: true, canMute: true))
        uptime.advance(MediaKeyHandler.recentVolumeWindow)         // later, the device's own values count again
        #expect(handler.handle(down(.soundDown)))
        #expect(volume.reads.last == true)
        #expect(volume.state?.level == 0.5625)
    }

    @Test func anotherOutputIsReadAfresh() {
        let uptime = FakeUptime()
        let handler = MediaKeyHandler(config: config, volume: volume, brightness: brightness, keyboard: keyboard,
                                      uptime: uptime.clock, sink: recorder.sink)
        _ = handler.handle(down(.soundUp))                         // 0.5 → 0.5625 on the built-in speakers
        volume.replace(with: VolumeState(level: 0.25, isMuted: false, canMute: true, deviceID: 9))   // AirPods connect
        uptime.advance(0.1)
        _ = handler.handle(down(.soundUp))
        #expect(volume.calls.last == "level(0.3125)")
    }

    @Test func aDisabledTapIsReported() {
        handler.tapWasDisabled()
        #expect(recorder.signals == [.tapDisabled])
    }

    @Test func voiceOverAdjustmentsApplyWithoutKeys() {
        let handler = handler
        handler.adjust(.volume, .up)
        handler.adjust(.volume, .toggle)
        handler.adjust(.brightness, .toggle)                       // brightness has no toggle: nothing happens
        #expect(volume.state == VolumeState(level: 0.5625, isMuted: true, canMute: true))
        #expect(recorder.updates.count == 2)
    }
}
