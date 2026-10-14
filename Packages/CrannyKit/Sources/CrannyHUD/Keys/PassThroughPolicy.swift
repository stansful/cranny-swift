// CrannyHUD/Keys/PassThroughPolicy.swift — which key presses Cranny takes and which it leaves to macOS
// (ARCHITECTURE.md §7.1 "Consume vs pass through", R3 §1.4). Pure and table-tested.
//
// Passing through = returning the event to the system: macOS changes the level AND shows its own HUD, and
// Cranny draws nothing. Cranny takes a key only when it can both apply the change and show the HUD.
// Device checks (no settable volume, no controllable display) happen after routing, in `MediaKeyHandler`,
// because they query hardware; key-ups follow their key-downs there too.
import Foundation

/// Why a key-down goes to macOS (kept for tests and `.debug` logs).
nonisolated enum PassReason: String, Sendable, Equatable {
    /// "Replace the system HUD" off, Accessibility missing or the HUD activity disabled.
    case notReplacing
    /// Play, next, previous and anything else the HUD does not own.
    case notOurKey
    /// The user turned this kind off (Settings ▸ HUD ▸ Volume / Brightness / Keyboard backlight).
    case kindDisabled
    /// Locked, asleep, or a full-screen app is in front under "Hide everything": Cranny cannot show a HUD.
    case notPresentable
    /// ⌥ alone: macOS opens the matching System Settings pane.
    case optionOpensSettings
}

nonisolated enum KeyRoute: Sendable, Equatable {
    case passThrough(PassReason)
    case handle(HUDKind, LevelAction)
}

nonisolated enum PassThroughPolicy {
    /// The kind and action a key controls, nil for keys the HUD never takes.
    static func target(of key: MediaKey) -> (kind: HUDKind, action: LevelAction)? {
        switch key {
        case .soundUp: (.volume, .up)
        case .soundDown: (.volume, .down)
        case .mute: (.volume, .toggle)
        case .brightnessUp: (.brightness, .up)
        case .brightnessDown: (.brightness, .down)
        case .illuminationUp: (.keyboardBacklight, .up)
        case .illuminationDown: (.keyboardBacklight, .down)
        case .illuminationToggle: (.keyboardBacklight, .toggle)
        case .play, .next, .previous, .fast, .rewind: nil
        }
    }

    /// The route of a key-down. (A key-up is consumed exactly when its key-down was.)
    static func route(_ event: MediaKeyEvent, config: HUDTapConfig) -> KeyRoute {
        guard config.isReplacing else { return .passThrough(.notReplacing) }
        guard let target = target(of: event.key) else { return .passThrough(.notOurKey) }
        guard config.handles(target.kind) else { return .passThrough(.kindDisabled) }
        guard config.isPresentable else { return .passThrough(.notPresentable) }
        guard !event.isOptionOnly else { return .passThrough(.optionOpensSettings) }
        return .handle(target.kind, target.action)
    }
}
