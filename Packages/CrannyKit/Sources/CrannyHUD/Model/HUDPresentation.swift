// CrannyHUD/Model/HUDPresentation.swift — what the HUD shows and for how long (DESIGN.md §10, §4.3).
// A pure reducer: key updates, level observations and device changes in, the next session plus side effects
// out. `HUDController` runs it on the main actor and executes the effects; tests drive it directly.
//
// A "session" is one HUD on screen: the first press opens it (`hudIn`), later presses only move the bar and
// the digits (`hudLevel`), and it ends `duration` after the last press (`hudOut`).
import Foundation

/// The values the HUD views draw.
nonisolated struct HUDDisplay: Sendable, Equatable {
    var kind: HUDKind
    /// 0…1.
    var level: Double
    /// Volume only.
    var isMuted: Bool = false
    /// ⌥⇧ was used in this session: the bar shows its 16 ticks until the HUD hides.
    var showsFineTicks: Bool = false
    /// Edge of the last "pressed past the end" bump; `bumpSerial` replays it once per press.
    var bumpEdge: LevelEdge = .top
    /// Animation trigger of the 2-pt bump. A view replays on ANY change, so it comes from the ever-growing
    /// `HUDPresentationState.bumpSerial` and never goes back (not even when a new display starts).
    var bumpSerial: Int = 0
    /// The output device's glyph instead of the speaker (first unmuted volume HUD after a device change).
    /// Mute still shows `speaker.slash.fill` (`symbolName`).
    var deviceGlyph: String?
    /// Plays one `.bounce` on the glyph per increment; like `bumpSerial`, it only ever grows.
    var glyphBounce: Int = 0

    var percent: Int { LevelStepper.percent(level) }
}

/// One HUD on screen.
nonisolated struct HUDSession: Sendable, Equatable {
    var display: HUDDisplay
    /// When the HUD hides (refreshed by every press).
    var deadline: Date
    /// Increments per press (`LiveActivity.revision`).
    var revision: Int
    /// The newest `HUDUpdate.sequence` shown (older updates are dropped).
    var sequence: UInt64

    func isVisible(at now: Date) -> Bool { deadline > now }
}

/// Side effects the controller performs after a reduction.
nonisolated enum HUDEffect: Sendable, Equatable {
    /// `.levelChange` detent: the press reached 0 % / 100 %, or pushed against it (DESIGN.md §14.2).
    case levelChangeHaptic
    /// Hide at this date (one sleep; refreshed per press).
    case scheduleHide(Date)
    /// The value changed: VoiceOver announces it once it has settled (0.5 s).
    case announceWhenSettled
}

/// The state that outlives sessions.
nonisolated struct HUDPresentationState: Sendable, Equatable {
    var session: HUDSession?
    /// Revisions keep counting across sessions (a new HUD must look like a change to the arbiter).
    var revision = 0
    /// The glyph of an output device that became default and has not been shown yet.
    var pendingDeviceGlyph: String?
    /// The views' animation triggers (`HUDDisplay.bumpSerial`, `.glyphBounce`). They only grow, across kinds and
    /// sessions: `keyframeAnimator(trigger:)` and `symbolEffect(_:value:)` replay on a reset to 0 as well.
    var bumpSerial = 0
    var glyphBounce = 0
}

nonisolated enum HUDPresentation {
    /// A press (or VoiceOver adjustment) was applied.
    static func receive(_ update: HUDUpdate, state: HUDPresentationState, now: Date,
                        duration: TimeInterval) -> (HUDPresentationState, [HUDEffect]) {
        var state = state
        let live = state.session.flatMap { $0.isVisible(at: now) ? $0 : nil }
        if let live, update.sequence <= live.sequence { return (state, []) }       // stale, reordered

        let continues = live?.display.kind == update.kind
        var display = (continues ? live?.display : nil) ?? HUDDisplay(kind: update.kind, level: update.level)
        display.level = update.level
        display.isMuted = update.kind == .volume && update.isMuted
        display.showsFineTicks = display.showsFineTicks || update.isFineStep

        var effects: [HUDEffect] = []
        if case .pressedPast(let edge)? = update.limit {
            display.bumpEdge = edge
            state.bumpSerial += 1
        }
        showPendingDeviceGlyph(on: &display, state: &state)
        display.bumpSerial = state.bumpSerial
        display.glyphBounce = state.glyphBounce
        if let limit = update.limit, !(update.isRepeat && limit == .pressedPast(limit.edge)) {
            effects.append(.levelChangeHaptic)                    // no second detent while a key is held at the end
        }

        state.revision += 1
        let deadline = now.addingTimeInterval(duration)
        state.session = HUDSession(display: display, deadline: deadline, revision: state.revision, sequence: update.sequence)
        effects.append(.scheduleHide(deadline))
        effects.append(.announceWhenSettled)
        return (state, effects)
    }

    /// The default output changed level or device outside Cranny (Control Center, AirPods, another app).
    /// Only a visible volume HUD follows it; no HUD appears for it (D10: there is no passive HUD).
    static func observe(_ observation: VolumeObservation, state: HUDPresentationState, now: Date,
                        showsOutputDevice: Bool) -> HUDPresentationState {
        var state = state
        if observation.deviceChanged {
            state.pendingDeviceGlyph = showsOutputDevice ? observation.device.glyph : nil
        }
        guard var session = state.session, session.isVisible(at: now), session.display.kind == .volume else {
            return state
        }
        if let level = observation.level { session.display.level = LevelStepper.clamp(level) }
        session.display.isMuted = observation.isMuted
        if observation.deviceChanged { session.display.deviceGlyph = nil }     // the old device's glyph is wrong now
        showPendingDeviceGlyph(on: &session.display, state: &state)
        session.display.glyphBounce = state.glyphBounce
        state.session = session
        return state
    }

    /// A new output device's glyph goes onto the first UNMUTED volume HUD, with one bounce. While muted it waits:
    /// mute shows `speaker.slash.fill` (DESIGN.md §10), and with Differentiate Without Color the bar's colour must
    /// not be the only sign of it (§16).
    private static func showPendingDeviceGlyph(on display: inout HUDDisplay, state: inout HUDPresentationState) {
        guard display.kind == .volume, !display.isMuted, let glyph = state.pendingDeviceGlyph else { return }
        display.deviceGlyph = glyph
        state.glyphBounce += 1
        state.pendingDeviceGlyph = nil
    }

    /// A polled brightness level while a brightness HUD is visible (the only allowed polling, 2 Hz, §9.2).
    static func observeBrightness(_ level: Double, state: HUDPresentationState, now: Date) -> HUDPresentationState {
        var state = state
        guard var session = state.session, session.isVisible(at: now), session.display.kind == .brightness,
              abs(session.display.level - level) > 0.001 else { return state }
        session.display.level = LevelStepper.clamp(level)
        state.session = session
        return state
    }

    /// The hide deadline passed (or the HUD was dismissed): the session ends.
    static func hide(_ state: HUDPresentationState, now: Date) -> HUDPresentationState {
        var state = state
        if let session = state.session, !session.isVisible(at: now) { state.session = nil }
        return state
    }
}
