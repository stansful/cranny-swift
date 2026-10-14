// Sessions, deadlines, the bump, detents, fine ticks and output-device glyphs (DESIGN.md §10, §4.3).
import Foundation
import Testing
@testable import CrannyHUD

@Suite struct HUDPresentationTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let duration: TimeInterval = 1.5

    private func update(_ sequence: UInt64, _ kind: HUDKind = .volume, level: Double = 0.5, muted: Bool = false,
                        fine: Bool = false, limit: LevelLimit? = nil, repeat isRepeat: Bool = false) -> HUDUpdate {
        HUDUpdate(sequence: sequence, kind: kind, level: level, isMuted: muted, isFineStep: fine, limit: limit, isRepeat: isRepeat)
    }

    private func receive(_ update: HUDUpdate, _ state: HUDPresentationState = HUDPresentationState(),
                         at offset: TimeInterval = 0) -> (HUDPresentationState, [HUDEffect]) {
        HUDPresentation.receive(update, state: state, now: t0.addingTimeInterval(offset), duration: duration)
    }

    private func observation(level: Double? = 0.25, muted: Bool = false, glyph name: String = "AirPods Pro",
                             transport: UInt32 = 0x626C_7565 /* 'blue' */, changed: Bool) -> VolumeObservation {
        VolumeObservation(level: level, isMuted: muted, device: OutputDevice(id: 7, name: name, transport: transport),
                          deviceChanged: changed)
    }

    @Test func firstPressOpensASession() throws {
        let (state, effects) = receive(update(1, level: 0.5625))
        let session = try #require(state.session)
        #expect(session.display == HUDDisplay(kind: .volume, level: 0.5625))
        #expect(session.revision == 1)
        #expect(session.deadline == t0.addingTimeInterval(duration))
        #expect(effects == [.scheduleHide(t0.addingTimeInterval(duration)), .announceWhenSettled])
    }

    @Test func laterPressesExtendTheSameSession() throws {
        let (first, _) = receive(update(1, level: 0.5, fine: true))
        let (second, effects) = receive(update(2, level: 0.515625), first, at: 1)
        let session = try #require(second.session)
        #expect(session.revision == 2)
        #expect(session.deadline == t0.addingTimeInterval(1 + duration))
        #expect(session.display.level == 0.515625)
        #expect(session.display.showsFineTicks)                    // sticky for the session
        #expect(effects.contains(.scheduleHide(t0.addingTimeInterval(1 + duration))))
    }

    @Test func staleUpdatesAreDropped() {
        let (state, _) = receive(update(5, level: 0.75))
        let (next, effects) = receive(update(4, level: 0.25), state, at: 0.1)
        #expect(next == state)
        #expect(effects.isEmpty)
    }

    @Test func aNewSessionStartsFresh() throws {
        let (first, _) = receive(update(1, fine: true))
        let (second, _) = receive(update(2, level: 0.25), first, at: duration + 0.01)
        let session = try #require(second.session)
        #expect(!session.display.showsFineTicks)
        #expect(session.revision == 2)                              // revisions keep counting
    }

    @Test func pressingPastAnEndBumpsAndTicks() throws {
        let (state, effects) = receive(update(1, level: 1, limit: .pressedPast(.top)))
        let display = try #require(state.session?.display)
        #expect(display.bumpSerial == 1)
        #expect(display.bumpEdge == .top)
        #expect(effects.first == .levelChangeHaptic)
        let (held, heldEffects) = receive(update(2, level: 1, limit: .pressedPast(.top), repeat: true), state, at: 0.05)
        #expect(held.session?.display.bumpSerial == 2)              // the bar still bumps on auto-repeat …
        #expect(!heldEffects.contains(.levelChangeHaptic))          // … but the detent plays once
        let (bottom, _) = receive(update(3, level: 0, limit: .pressedPast(.bottom)), held, at: 0.1)
        #expect(bottom.session?.display.bumpEdge == .bottom)
    }

    @Test func reachingAnEndIsADetentWithoutBump() throws {
        let (state, effects) = receive(update(1, level: 1, limit: .reached(.top)))
        #expect(effects.first == .levelChangeHaptic)
        #expect(try #require(state.session).display.bumpSerial == 0)
        let (_, middle) = receive(update(2, level: 0.5), state, at: 0.1)
        #expect(!middle.contains(.levelChangeHaptic))
    }

    @Test func switchingKindsKeepsTheHUDButResetsItsContent() throws {
        let (volume, _) = receive(update(1, fine: true))
        let (brightness, _) = receive(update(2, .brightness, level: 0.75), volume, at: 0.2)
        let session = try #require(brightness.session)
        #expect(session.display == HUDDisplay(kind: .brightness, level: 0.75))
        #expect(session.revision == 2)
    }

    @Test func muteIsVolumeOnly() {
        #expect(receive(update(1, muted: true)).0.session?.display.isMuted == true)
        #expect(receive(update(1, .brightness, muted: true)).0.session?.display.isMuted == false)
    }

    @Test func aDeviceChangeShowsOnTheNextVolumeHUD() throws {
        var state = HUDPresentation.observe(observation(changed: true), state: HUDPresentationState(), now: t0, showsOutputDevice: true)
        #expect(state.session == nil)                                // no HUD of its own (no passive HUD, D10)
        #expect(state.pendingDeviceGlyph == "airpodspro")
        let (brightness, _) = receive(update(1, .brightness), state)
        #expect(brightness.session?.display.deviceGlyph == nil)    // not for brightness …
        state = brightness
        let (volume, _) = receive(update(2), state, at: duration + 1)
        let display = try #require(volume.session?.display)
        #expect(display.deviceGlyph == "airpodspro")                // … for the next volume HUD, once
        #expect(display.glyphBounce == 1)
        #expect(volume.pendingDeviceGlyph == nil)
        let (later, _) = receive(update(3), volume, at: 2 * duration + 3)
        #expect(later.session?.display.deviceGlyph == nil)
    }

    @Test func aDeviceChangeUpdatesTheVisibleVolumeHUD() throws {
        let (state, _) = receive(update(1, level: 0.75))
        let next = HUDPresentation.observe(observation(level: 0.25, changed: true), state: state, now: t0.addingTimeInterval(0.5),
                                           showsOutputDevice: true)
        let display = try #require(next.session?.display)
        #expect(display.level == 0.25)
        #expect(display.deviceGlyph == "airpodspro")
        #expect(display.glyphBounce == 1)
        #expect(next.session?.revision == state.session?.revision)  // not a press: no new revision
    }

    @Test func outputDeviceGlyphsCanBeTurnedOff() {
        let state = HUDPresentation.observe(observation(changed: true), state: HUDPresentationState(), now: t0, showsOutputDevice: false)
        #expect(state.pendingDeviceGlyph == nil)
    }

    @Test func levelChangesFollowOnlyAVisibleVolumeHUD() {
        let idle = HUDPresentation.observe(observation(changed: false), state: HUDPresentationState(), now: t0, showsOutputDevice: true)
        #expect(idle == HUDPresentationState())
        let (brightness, _) = receive(update(1, .brightness, level: 0.5))
        let unchanged = HUDPresentation.observe(observation(changed: false), state: brightness, now: t0, showsOutputDevice: true)
        #expect(unchanged == brightness)
        let (volume, _) = receive(update(2, level: 0.5), brightness, at: 0.1)
        let followed = HUDPresentation.observe(observation(level: nil, muted: true, changed: false), state: volume,
                                               now: t0.addingTimeInterval(0.2), showsOutputDevice: true)
        #expect(followed.session?.display.level == 0.5)             // HDMI: no readable level, keep ours
        #expect(followed.session?.display.isMuted == true)
    }

    @Test func polledBrightnessFollowsOnlyABrightnessHUD() {
        let (brightness, _) = receive(update(1, .brightness, level: 0.5))
        #expect(HUDPresentation.observeBrightness(0.8, state: brightness, now: t0).session?.display.level == 0.8)
        let (volume, _) = receive(update(1, level: 0.5))
        #expect(HUDPresentation.observeBrightness(0.8, state: volume, now: t0) == volume)
        #expect(HUDPresentation.observeBrightness(0.8, state: brightness, now: t0.addingTimeInterval(duration + 1)) == brightness)
    }

    @Test func hidingWaitsForTheDeadline() {
        let (state, _) = receive(update(1))
        #expect(HUDPresentation.hide(state, now: t0.addingTimeInterval(1)).session != nil)
        #expect(HUDPresentation.hide(state, now: t0.addingTimeInterval(duration)).session == nil)
        #expect(HUDPresentation.hide(state, now: t0.addingTimeInterval(duration)).revision == 1)
    }
}
