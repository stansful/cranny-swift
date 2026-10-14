// CrannyAppShell/State/PeekScheduler.swift — where an auto-peek may play (ARCHITECTURE.md §4.6 step 4, §4.7,
// DESIGN.md §9.4). Pure: the coordinator passes each display's facts. VoiceOver hears about alerts through Core's
// `services.announcer` (one app-wide limit, DESIGN.md §16).
import CrannyCore
import Foundation

nonisolated enum PeekScheduler {
    /// One display as the peek policy sees it.
    struct Display: Equatable, Sendable {
        var key: DisplayKey
        var isPointerDisplay: Bool
        var isOpen: Bool
        /// Hidden for any reason (lock, full screen under `.hideAll`, `.pointer` selection …).
        var isHidden: Bool
        /// `DisplayPreferences.showsPeeks`.
        var showsPeeks: Bool
        /// The display's lineup (an activity it does not show never peeks there, e.g. P2 under `.alertsAndHUD`).
        var lineup: Lineup
    }

    /// The display an auto-peek of `id` plays on, or nil: only the pointer's display, never while it is open,
    /// hidden or not showing peeks, never while Live Activities are paused, and only for an activity that
    /// display shows (§4.7). Arbiter peeks and `NotchControl.requestPeek` follow the same policy; the flash that
    /// confirms a pause or resume passes `paused: false` (it outlasts the pause it confirms).
    static func target(for id: ActivityID, among displays: [Display], paused: Bool) -> DisplayKey? {
        guard !paused, let display = displays.first(where: \.isPointerDisplay) else { return nil }
        guard !display.isOpen, !display.isHidden, display.showsPeeks, display.lineup.contains(id) else { return nil }
        return display.key
    }
}
