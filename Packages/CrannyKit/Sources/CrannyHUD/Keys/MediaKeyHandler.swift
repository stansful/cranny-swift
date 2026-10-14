// CrannyHUD/Keys/MediaKeyHandler.swift — decides and applies one key event on the key tap's thread
// (ARCHITECTURE.md §7.1). Returns true to consume the event, which suppresses both the system's change and its
// HUD; Cranny then applies the change itself and reports it to the main actor through `sink`.
//
// Thread: called on the tap thread (`MediaKeyInterceptor`) and, for VoiceOver adjustments, on a concurrent
// executor (`HUDController.adjust`), never on the main actor. It must return within microseconds: it reads the
// config snapshot, calls CoreAudio / DisplayServices (thread-safe C APIs, only the reads a press needs: a repeat
// skips the volume and mute it would replace) and never blocks on the main actor. Its
// own state (keys whose key-down was consumed, the update counter, the volume it last applied) sits behind an
// unfair lock. Tests drive it with fakes; it never touches a real device there.
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
        /// The volume Cranny last applied. A press within `recentVolumeWindow` on the same device steps from it
        /// instead of a fresh read: Bluetooth outputs report a new level late, and stepping from a stale read would
        /// repeat the same step while a key is held (and a double-tapped mute would not toggle back).
        var lastVolume: AppliedVolume?
    }

    private struct AppliedVolume {
        var deviceID: UInt32?
        var level: Double
        var isMuted: Bool
        /// `uptime` when it was applied.
        var time: TimeInterval
    }

    /// How long the volume Cranny applied is trusted over the device's own report (key repeat runs at ~30 Hz).
    static let recentVolumeWindow: TimeInterval = 0.5

    private let config: HUDTapConfigBox
    private let volume: any SystemVolume
    private let brightness: any DisplayBrightness
    private let keyboard: any KeyboardBacklight
    private let sink: Sink
    /// A monotonic clock in seconds (tests drive their own).
    private let uptime: @Sendable () -> TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(config: HUDTapConfigBox, volume: any SystemVolume, brightness: any DisplayBrightness,
         keyboard: any KeyboardBacklight, uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sink: @escaping Sink) {
        self.config = config; self.volume = volume; self.brightness = brightness; self.keyboard = keyboard
        self.uptime = uptime; self.sink = sink
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

    /// The tap saw `tapDisabledBy…` (and re-enabled itself): the main actor re-checks the Accessibility grant.
    func tapWasDisabled() { sink(.tapDisabled) }

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
        let now = uptime()
        // Within the window a press steps from what Cranny applied, so it reads only the device and what it can
        // set, not the level and mute it would replace (every repeat of a held key lands here).
        let recent = state.withLock { state in
            state.lastVolume.flatMap { now - $0.time < Self.recentVolumeWindow ? $0 : nil }
        }
        guard var before = volume.readState(includingLevels: recent == nil) else { return nil }   // HDMI / DisplayPort
        if let recent {
            if recent.deviceID == before.deviceID {
                before.level = recent.level
                before.isMuted = recent.isMuted
            } else {
                guard let fresh = volume.readState() else { return nil }       // another output: its own values
                before = fresh
            }
        }
        let device = before.deviceID                                         // writes go where the values came from
        var after = before
        var limit: LevelLimit?
        switch action {
        case .toggle:
            guard before.canMute else { return nil }
            if !isRepeat {                                                   // holding mute does not flicker
                guard volume.setMuted(!before.isMuted, on: device) else { return nil }
                after.isMuted.toggle()
            }
        case .up, .down:
            let up = action == .up
            if up && before.isMuted {                                        // volume-up unmutes (macOS convention)
                guard volume.setMuted(false, on: device) else { return nil }
                after.isMuted = false
            }
            let target = LevelStepper.step(before.level, up: up, fine: fine)
            if target != before.level {
                guard volume.setLevel(target, on: device) else { return nil }
            }
            after.level = target            // not a read-back: Bluetooth outputs report the new level late
            limit = LevelStepper.limit(from: before.level, to: target, up: up)
        }
        let applied = AppliedVolume(deviceID: device, level: after.level, isMuted: after.isMuted, time: now)
        state.withLock { $0.lastVolume = applied }
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
