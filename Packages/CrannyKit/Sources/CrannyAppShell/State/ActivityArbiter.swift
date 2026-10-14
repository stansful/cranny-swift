// CrannyAppShell/State/ActivityArbiter.swift — global activity arbitration (ARCHITECTURE.md §4.6–§4.7), pure.
// The coordinator snapshots every registered activity (`ActivitySnapshot`) whenever one of them changes,
// calls `update(_:settings:now:)` once per change and turns the result into one `Lineup` per display.
// The arbiter remembers swipe-up dismissals, the last revision it saw (peeks fire on a NEW revision only)
// and the user's satellite swap.
import CoreGraphics
import CrannyCore
import Foundation

/// What the arbiter needs of one registered activity (read through Observation, so changes re-arbitrate).
nonisolated struct ActivitySnapshot: Equatable, Sendable {
    var id: ActivityID
    /// Order of registration (ties within a priority class when the user has no order for it).
    var registrationIndex: Int
    var isActive: Bool
    var priority: ActivityPriority
    var slot: SlotWidth
    var revision: Int
    var expiresAt: Date?
    /// Settings ▸ Live Activities toggle (`prefs[id]?.isEnabled ?? kind.isEnabledByDefault`).
    var isEnabled: Bool
    /// "Peek on change" (`prefs[id]?.peeksOnChange ?? kind.peeksOnChangeByDefault`).
    var peeksOnChange: Bool
    var delight: DelightMoment?
}

/// The arbitration-relevant settings (§4.6 input line).
nonisolated struct ArbiterSettings: Equatable, Sendable {
    var order: [ActivityID] = []
    var paused = false
    var satellite = true
    var autoUnhide = true
}

/// What one display shows (§4.6 step 3): the wings, the satellite and the rest (hover peek ≤ 4 rows).
nonisolated struct Lineup: Equatable, Sendable {
    var primary: ActivityID?
    var satellite: ActivityID?
    var overflow: [ActivityID] = []
    var primarySlot: SlotWidth = .short

    /// Rows of a hover peek: every visible activity, at most 4 (§4.2, DESIGN.md §9.4).
    var hoverPeekRows: [ActivityID] { Array(([primary, satellite].compactMap { $0 } + overflow).prefix(4)) }
    func contains(_ id: ActivityID) -> Bool { primary == id || satellite == id || overflow.contains(id) }
}

/// Per-display rules of §4.6 step 5 and §4.9.
nonisolated struct DisplayFilter: Equatable, Sendable {
    var key: DisplayKey
    /// Peeks, alerts (P1) and the HUD (P0) appear only on the pointer's display.
    var isPointerDisplay: Bool
    /// `.alertsAndHUD` with a full-screen app in front: P0/P1 only.
    var restrictsToAlerts = false
    var showsActivities = true
    var showsHUD = true
    /// The display that shows `NotchControl.flash` (chosen when it was requested).
    var flashDisplay: DisplayKey?
}

nonisolated struct ActivityArbiter {
    /// One arbitration's outcome.
    struct Outcome: Equatable {
        /// Every candidate, best first (step 2).
        var ranked: [ActivitySnapshot] = []
        /// Activities whose revision changed and that ask for an auto-peek (step 4).
        var peeks: [ActivityID] = []
        /// P1 activities with a new revision: VoiceOver announcements (≤ 1 per 10 s, `AnnouncementLimiter`).
        var announcements: [ActivityID] = []
        /// Visible-candidate revisions that name a delight (step 7).
        var delights: [ActivityID] = []
        /// Candidates with a new revision (they unhide the idle handle and collapsed wings).
        var changed: [ActivityID] = []
        /// The one wake-up to schedule: the earliest `expiresAt` in the future (step 6).
        var nextExpiry: Date?
    }

    /// Swipe-up dismissals: the revision the activity had when it was dismissed (§4.7).
    private(set) var dismissed: [ActivityID: Int] = [:]
    /// The last revision seen per activity; initialised at the first update, so nothing peeks at launch.
    private(set) var lastSeen: [ActivityID: Int] = [:]
    /// The user clicked the satellite: show `satellite` in the wings while these two are the top pair.
    private(set) var swap: (primary: ActivityID, satellite: ActivityID)?
    private var started = false

    // MARK: Arbitration

    mutating func update(_ activities: [ActivitySnapshot], settings: ArbiterSettings, now: Date) -> Outcome {
        // Dismissals end with the next revision (auto-unhide) or when the activity goes away.
        for activity in activities {
            guard let revision = dismissed[activity.id] else { continue }
            if !activity.isActive || (settings.autoUnhide && revision != activity.revision) { dismissed[activity.id] = nil }
        }
        let candidates = activities.filter { a in
            a.isActive && a.isEnabled && (a.expiresAt.map { $0 > now } ?? true)
                && dismissed[a.id] == nil && (!settings.paused || a.priority == .hud)
        }
        var outcome = Outcome(ranked: Self.rank(candidates, order: settings.order))
        outcome.nextExpiry = candidates.compactMap(\.expiresAt).filter { $0 > now }.min()

        let candidateIDs = Set(candidates.map(\.id))
        for activity in activities {
            defer { lastSeen[activity.id] = activity.revision }
            guard started, let seen = lastSeen[activity.id], activity.revision != seen,
                  candidateIDs.contains(activity.id) else { continue }
            outcome.changed.append(activity.id)
            // The flash IS the transient presentation; it never peeks (onboarding "Hi", "Path copied").
            if activity.id != .flash, activity.priority != .hud,
               activity.priority == .alert || activity.peeksOnChange { outcome.peeks.append(activity.id) }
            if activity.priority == .alert, activity.id != .flash { outcome.announcements.append(activity.id) }
            if activity.delight != nil { outcome.delights.append(activity.id) }
        }
        started = true
        if let swap, !(candidateIDs.contains(swap.primary) && candidateIDs.contains(swap.satellite)) { self.swap = nil }
        return outcome
    }

    /// Step 2: priority class first, then the user's order, then registration order.
    static func rank(_ candidates: [ActivitySnapshot], order: [ActivityID]) -> [ActivitySnapshot] {
        candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            let l = order.firstIndex(of: lhs.id), r = order.firstIndex(of: rhs.id)
            switch (l, r) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.registrationIndex < rhs.registrationIndex
            }
        }
    }

    // MARK: Per display (§4.6 steps 3 and 5, §4.9)

    func lineup(_ ranked: [ActivitySnapshot], on display: DisplayFilter, satellite enabled: Bool) -> Lineup {
        let visible = ranked.filter { Self.isVisible($0, on: display) }
        var top = Array(visible.prefix(2))
        if top.count == 2, let swap, top[0].id == swap.primary, top[1].id == swap.satellite { top.swapAt(0, 1) }
        let satellite = enabled && top.count == 2 ? top[1].id : nil
        let rest = visible.dropFirst(2).map(\.id)
        return Lineup(primary: top.first?.id, satellite: satellite,
                      overflow: (enabled ? [] : top.dropFirst().map(\.id)) + rest,
                      primarySlot: top.first?.slot ?? .short)
    }

    static func isVisible(_ activity: ActivitySnapshot, on display: DisplayFilter) -> Bool {
        if activity.id == .flash { return display.key == display.flashDisplay }
        if activity.priority == .hud { return showsHUD(on: display) }
        guard display.showsActivities else { return false }
        if activity.priority == .alert { return display.isPointerDisplay }
        return !display.restrictsToAlerts
    }

    /// The HUD (P0) appears only on the pointer's display, and only where General ▸ Displays ▸ HUD is on. The HUD
    /// module learns the same answer through `SystemEnvironment.canPresentHUD`, so it never takes a key nobody shows.
    static func showsHUD(on display: DisplayFilter) -> Bool { display.showsHUD && display.isPointerDisplay }

    // MARK: User actions

    /// Swipe-up (or VoiceOver "Dismiss"): hidden until its revision changes (§4.7).
    mutating func dismiss(_ id: ActivityID, revision: Int) {
        dismissed[id] = revision
        if swap?.primary == id || swap?.satellite == id { swap = nil }
    }

    /// Click on the satellite: the two swap places until the pair changes (§4.4).
    mutating func swapSatellite(primary: ActivityID, satellite: ActivityID) {
        if let swap, swap.primary == satellite, swap.satellite == primary { self.swap = nil }      // swap back
        else { swap = (primary, satellite) }
    }
}
