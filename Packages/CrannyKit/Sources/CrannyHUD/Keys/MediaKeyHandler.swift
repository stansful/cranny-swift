// CrannyHUD/Keys/MediaKeyHandler.swift — decides and applies one key event on the key tap's thread
// (ARCHITECTURE.md §7.1). Returns true to consume the event, which suppresses both the system's change and its
// HUD; Cranny then applies the change itself and reports it to the main actor through `sink`.
//
// Thread: called on the tap thread (`MediaKeyInterceptor`) and, for VoiceOver adjustments, on the main actor.
// It must return within microseconds: it reads the config snapshot, calls CoreAudio / DisplayServices
// (thread-safe C APIs) and never blocks on the main actor. Its own state (keys whose key-down was consumed,
// the update counter) sits behind an unfair lock. Tests drive it with fakes; it never touches a real device there.
import Foundation
import os

nonisolated final class MediaKeyHandler: Sendable {
    typealias Sink = @Sendable (HUDSignal) -> Void

    private struct State {
        /// Keys whose last key-down was consumed: their key-up is consumed too (symmetry), whatever the config
        /// says by then — macOS must never see a key-up without its key-down or the reverse.
        var consumedKeys: Set<MediaKey> = []
        var sequence: UInt64 = 0
        /// Keyboard backlight level before the toggle key turned it off.
        var backlightBeforeOff: Double?
    }

    private let config: HUDTapConfigBox
    private let volume: any SystemVolume
    private let brightness: any DisplayBrightness
    private let keyboard: any KeyboardBacklight
    private let sink: Sink
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(config: HUDTapConfigBox, volume: any SystemVolume, brightness: any DisplayBrightness,
         keyboard: any KeyboardBacklight, sink: @escaping Sink) {
        self.config = config; self.volume = volume; self.brightness = brightness; self.keyboard = keyboard; self.sink = sink
    }

    /// true = consume (Cranny applied the change and shows the HUD); false = macOS handles the key.
    func handle(_ event: MediaKeyEvent) -> Bool {
        guard event.isDown else { return release(event) }
        guard case .handle(let kind, let action) = PassThroughPolicy.route(event, config: config.current),
              let update = apply(kind, action, fine: event.isFineStep, isRepeat: event.isRepeat) else {
            state.withLock { _ = $0.consumedKeys.remove(event.key) }
            return false
        }
        state.withLock { _ = $0.consumedKeys.insert(event.key) }
        sink(.changed(update))
        return true
    }

    /// A VoiceOver "Increase / Decrease / Mute" action from the HUD: the same rules without a key.
    func adjust(_ kind: HUDKind, _ action: LevelAction) {
        if let update = apply(kind, action, fine: false, isRepeat: false) { sink(.changed(update)) }
    }

    // MARK: Key-up

    private func release(_ event: MediaKeyEvent) -> Bool {
        let consumed = state.withLock { $0.consumedKeys.remove(event.key) != nil }
        if consumed, event.key == .soundUp || event.key == .soundDown {
            sink(.volumeKeyReleased(shiftHeld: event.isShiftHeld))
        }
        return consumed
    }

    // MARK: Applying a change (nil = could not: the key goes to macOS)

    private func apply(_ kind: HUDKind, _ action: LevelAction, fine: Bool, isRepeat: Bool) -> HUDUpdate? {
        switch kind {
        case .volume: applyVolume(action, fine: fine, isRepeat: isRepeat)
        case .brightness: applyLevel(.brightness, action, fine: fine, isRepeat: isRepeat,
                                     read: brightness.readLevel, write: brightness.setLevel)
        case .keyboardBacklight: applyKeyboard(action, fine: fine, isRepeat: isRepeat)
        }
    }

    private func applyVolume(_ action: LevelAction, fine: Bool, isRepeat: Bool) -> HUDUpdate? {
        guard let before = volume.readState() else { return nil }          // HDMI / DisplayPort: not settable
        var after = before
        var limit: LevelLimit?
        switch action {
        case .toggle:
            guard before.canMute else { return nil }
            if !isRepeat {                                                   // holding mute does not flicker
                guard volume.setMuted(!before.isMuted) else { return nil }
                after.isMuted.toggle()
            }
        case .up, .down:
            let up = action == .up
            if up && before.isMuted {                                        // volume-up unmutes (macOS convention)
                guard volume.setMuted(false) else { return nil }
                after.isMuted = false
            }
            let target = LevelStepper.step(before.level, up: up, fine: fine)
            if target != before.level {
                guard volume.setLevel(target) else { return nil }
            }
            after.level = target            // not a read-back: Bluetooth outputs report the new level late
            limit = LevelStepper.limit(from: before.level, to: target, up: up)
        }
        return makeUpdate(.volume, level: after.level, muted: after.isMuted, fine: fine, limit: limit, isRepeat: isRepeat)
    }

    private func applyKeyboard(_ action: LevelAction, fine: Bool, isRepeat: Bool) -> HUDUpdate? {
        guard action == .toggle else {
            return applyLevel(.keyboardBacklight, action, fine: fine, isRepeat: isRepeat,
                              read: keyboard.readLevel, write: keyboard.setLevel)
        }
        guard let before = keyboard.readLevel() else { return nil }
        guard !isRepeat else { return makeUpdate(.keyboardBacklight, level: before, fine: false, limit: nil, isRepeat: true) }
        let restored = state.withLock { $0.backlightBeforeOff } ?? 0.5
        let target = before > 0 ? 0 : restored
        guard keyboard.setLevel(target) else { return nil }
        state.withLock { $0.backlightBeforeOff = before > 0 ? before : nil }
        return makeUpdate(.keyboardBacklight, level: target, fine: false, limit: nil, isRepeat: false)
    }

    /// Brightness and the keyboard backlight: step on the 16-step grid and write. The HUD shows the target (the
    /// panel may still be fading to it); a level changed elsewhere reaches the visible HUD through polling.
    private func applyLevel(_ kind: HUDKind, _ action: LevelAction, fine: Bool, isRepeat: Bool,
                            read: () -> Double?, write: (Double) -> Bool) -> HUDUpdate? {
        guard action != .toggle, let before = read() else { return nil }
        let up = action == .up
        let target = LevelStepper.step(before, up: up, fine: fine)
        if target != before {
            guard write(target) else { return nil }
        }
        return makeUpdate(kind, level: target, fine: fine, limit: LevelStepper.limit(from: before, to: target, up: up), isRepeat: isRepeat)
    }

    private func makeUpdate(_ kind: HUDKind, level: Double, muted: Bool = false, fine: Bool, limit: LevelLimit?,
                            isRepeat: Bool) -> HUDUpdate {
        let sequence = state.withLock { state -> UInt64 in
            state.sequence += 1
            return state.sequence
        }
        return HUDUpdate(sequence: sequence, kind: kind, level: LevelStepper.clamp(level), isMuted: muted,
                         isFineStep: fine, limit: limit, isRepeat: isRepeat)
    }
}
