// CrannyHUD/Model/HUDKind.swift — the values that travel from the key tap's thread to the main actor.
// All `nonisolated` and `Sendable`: the tap thread creates them, the main actor presents them.
import Foundation

/// What a HUD shows (DESIGN.md §10).
nonisolated enum HUDKind: String, Sendable, CaseIterable, Equatable {
    case volume, brightness, keyboardBacklight
}

/// What a key asks for. `toggle` is mute for volume and on/off for the keyboard backlight.
nonisolated enum LevelAction: Sendable, Equatable {
    case up, down, toggle
}

/// The end of the scale a press reached or pushed against.
nonisolated enum LevelEdge: Sendable, Equatable {
    case bottom, top
}

/// How a press met the scale's ends: `reached` moves onto 0 % / 100 % (a `.levelChange` detent);
/// `pressedPast` pushes against an end the level is already on (the 2-pt bump, DESIGN.md §4.3).
nonisolated enum LevelLimit: Sendable, Equatable {
    case reached(LevelEdge)
    case pressedPast(LevelEdge)

    var edge: LevelEdge {
        switch self {
        case .reached(let edge), .pressedPast(let edge): edge
        }
    }
}

/// One applied key press (or a VoiceOver adjustment): the level after the change.
nonisolated struct HUDUpdate: Sendable, Equatable {
    /// Monotonic per handler: the main actor drops an update older than the last one it presented.
    var sequence: UInt64
    var kind: HUDKind
    /// 0…1 after the change.
    var level: Double
    /// Volume only.
    var isMuted: Bool = false
    /// ⌥⇧ quarter steps: the bar shows its 16 ticks.
    var isFineStep: Bool = false
    var limit: LevelLimit?
    /// A held key's auto-repeat (no second detent for the same limit).
    var isRepeat: Bool = false
}

/// What the key tap reports to the main actor.
nonisolated enum HUDSignal: Sendable, Equatable {
    /// A press was applied: show it.
    case changed(HUDUpdate)
    /// A consumed volume up/down key went up: macOS plays its feedback sound on release, so Cranny does.
    case volumeKeyReleased(shiftHeld: Bool)
    /// macOS disabled the key tap (timeout or user input) and the tap re-enabled itself. The main actor re-checks
    /// the Accessibility grant, which may have been revoked.
    case tapDisabled
}
