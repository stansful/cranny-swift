// CrannyHUD/UI/HUDActivity.swift — the HUD as a live activity (ARCHITECTURE.md §7.1, DESIGN.md §9.2 row
// "HUD", §10): P0, wide slot, transient. The shell arbitrates it like any other activity: while it is active it
// pre-empts everything for its lifetime, then hands the wings back (§9.4); inside an open panel NotchUI draws
// its leading and trailing views in the header row (§4.11).
//
// `HUDController` writes it; the views read it. Samples (Settings "Simulate", the HUD preview stage) are
// separate instances that never touch the controller or any device.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class HUDActivity: LiveActivity {
    /// Settings ▸ Live Activities row. Turning it off hands the keys back to macOS (its own HUD shows).
    static var kind: ActivityKind {
        ActivityKind(id: .hud, module: .hud,
                     title: String(localized: "Volume and brightness", bundle: .module,
                                   comment: "Live Activities pane: the HUD activity (volume, brightness and keyboard backlight levels)"),
                     symbol: "speaker.wave.2.fill", defaultPriority: .hud)
    }

    let id: ActivityID = .hud
    let priority: ActivityPriority = .hud
    let slot: SlotWidth = .wide
    private(set) var isActive = false
    private(set) var revision = 0
    private(set) var expiresAt: Date?
    /// What the views draw. Kept after the HUD hides, so its content does not blank during `hudOut`.
    private(set) var display: HUDDisplay?

    /// Settings the views read (colours, value, output device). Live, so the Settings stage follows changes.
    @ObservationIgnored let settings: SettingsStore
    /// VoiceOver "Increase / Decrease / Mute" (the real activity only; samples have no actions).
    @ObservationIgnored var adjust: (@MainActor (HUDKind, LevelAction) -> Void)?

    init(settings: SettingsStore) { self.settings = settings }

    /// The Settings ▸ Live Activities toggle of this activity. Off hands the keys back to macOS (its HUD shows).
    static func isEnabled(in settings: SettingsStore) -> Bool {
        settings[CoreSettings.activityPreferences][.hud]?.isEnabled ?? kind.isEnabledByDefault
    }

    /// A sample that never expires: the Settings stage, "Simulate ▸ Volume" and previews.
    static func sample(settings: SettingsStore, display: HUDDisplay = HUDDisplay(kind: .volume, level: 0.62)) -> HUDActivity {
        let sample = HUDActivity(settings: settings)
        sample.present(HUDSession(display: display, deadline: .distantFuture, revision: 1, sequence: 0), expires: false)
        return sample
    }

    /// Shows `session` (nil hides). The shell re-arbitrates on every change of these properties.
    func present(_ session: HUDSession?, expires: Bool = true) {
        guard let session else {
            if isActive { isActive = false }       // @Observable notifies on every write: write only changes
            if expiresAt != nil { expiresAt = nil }
            return
        }
        if display != session.display { display = session.display }
        if revision != session.revision { revision = session.revision }
        let deadline = expires ? session.deadline : nil
        if expiresAt != deadline { expiresAt = deadline }
        if !isActive { isActive = true }
    }

    // MARK: LiveActivity

    var accessibilityLabel: String { (display?.kind ?? .volume).title }
    var accessibilityValue: String? { display.map(HUDCopy.accessibilityValue) }

    var actions: [ActivityAction] {
        guard let adjust, let kind = display?.kind else { return [] }
        var actions = [
            ActivityAction(id: "increase", title: String(localized: "Increase", bundle: .module, comment: "HUD: VoiceOver action that raises the level"),
                           symbol: nil) { adjust(kind, .up) },
            ActivityAction(id: "decrease", title: String(localized: "Decrease", bundle: .module, comment: "HUD: VoiceOver action that lowers the level"),
                           symbol: nil) { adjust(kind, .down) },
        ]
        if kind == .volume {
            let muted = display?.isMuted ?? false
            actions.append(ActivityAction(
                id: "mute",
                title: muted ? String(localized: "Unmute", bundle: .module, comment: "HUD: VoiceOver action that turns the sound back on")
                             : String(localized: "Mute", bundle: .module, comment: "HUD: VoiceOver action that mutes the output"),
                symbol: muted ? "speaker.wave.3.fill" : "speaker.slash.fill") { adjust(.volume, .toggle) })
        }
        return actions
    }

    func compactLeading() -> some View { HUDLeadingView(activity: self) }
    func compactTrailing() -> some View { HUDTrailingView(activity: self) }
    func minimal() -> some View { HUDGlyph(activity: self) }
    func peekRow() -> some View { HUDPeekRow(activity: self) }
}

#Preview("HUD activity · output device") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .volume, level: 0.5, deviceGlyph: "airpodspro")))
}
