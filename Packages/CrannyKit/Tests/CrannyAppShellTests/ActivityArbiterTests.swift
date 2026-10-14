// Global arbitration (ARCHITECTURE.md §4.6–§4.7), the peek policy, the delight caps (§4.6 step 7) and the
// VoiceOver rate limit (DESIGN.md §16). Pure: snapshots, an injected `now`, no windows.
import CrannyCore
import Foundation
import Testing
@testable import CrannyAppShell

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

private func activity(_ id: ActivityID, _ priority: ActivityPriority = .ongoing, index: Int = 0, active: Bool = true,
                      revision: Int = 1, expiresAt: Date? = nil, enabled: Bool = true, peeks: Bool = false,
                      delight: DelightMoment? = nil, slot: SlotWidth = .short) -> ActivitySnapshot {
    ActivitySnapshot(id: id, registrationIndex: index, isActive: active, priority: priority, slot: slot, revision: revision,
                     expiresAt: expiresAt, isEnabled: enabled, peeksOnChange: peeks, delight: delight)
}

private let here = DisplayKey(rawValue: "display-here")
private let there = DisplayKey(rawValue: "display-there")
private func filter(_ key: DisplayKey = here, pointer: Bool = true, restricted: Bool = false, activities: Bool = true,
                    hud: Bool = true, flash: DisplayKey? = nil) -> DisplayFilter {
    DisplayFilter(key: key, isPointerDisplay: pointer, restrictsToAlerts: restricted, showsActivities: activities,
                  showsHUD: hud, flashDisplay: flash)
}

// MARK: - Candidates and ranking (steps 1–3)

@Test func candidatesAreActiveEnabledUnexpiredUndismissedAndUnpaused() {
    var arbiter = ActivityArbiter()
    let all = [
        activity("a.playing", index: 0),
        activity("b.inactive", index: 1, active: false),
        activity("c.disabled", index: 2, enabled: false),
        activity("d.expired", .alert, index: 3, expiresAt: t0.addingTimeInterval(-1)),
        activity("e.later", .alert, index: 4, expiresAt: t0.addingTimeInterval(5)),
        activity("f.hud", .hud, index: 5),
    ]
    let outcome = arbiter.update(all, settings: ArbiterSettings(), now: t0)
    #expect(outcome.ranked.map(\.id) == ["f.hud", "e.later", "a.playing"])
    #expect(outcome.nextExpiry == t0.addingTimeInterval(5))                    // ONE wake-up, the earliest
    let paused = arbiter.update(all, settings: ArbiterSettings(paused: true), now: t0)
    #expect(paused.ranked.map(\.id) == ["f.hud"])                              // the HUD still works while paused
}

@Test func rankingIsPriorityThenTheUsersOrderThenRegistration() {
    let snapshots = [activity("timer", index: 0), activity("media", index: 1), activity("meeting", index: 2),
                     activity("battery", .alert, index: 3), activity("paused", .passive, index: 4)]
    #expect(ActivityArbiter.rank(snapshots, order: []).map(\.id) == ["battery", "timer", "media", "meeting", "paused"])
    #expect(ActivityArbiter.rank(snapshots, order: ["meeting", "media"]).map(\.id) == ["battery", "meeting", "media", "timer", "paused"])
}

@Test func theSecondActivityBecomesTheSatelliteAndTheRestOverflow() {
    var arbiter = ActivityArbiter()
    let ranked = arbiter.update([activity("a", index: 0), activity("b", index: 1, slot: .medium), activity("c", index: 2),
                                 activity("d", index: 3), activity("e", index: 4)],
                                settings: ArbiterSettings(), now: t0).ranked
    let lineup = arbiter.lineup(ranked, on: filter(), satellite: true)
    #expect(lineup.primary == "a" && lineup.satellite == "b" && lineup.overflow == ["c", "d", "e"])
    #expect(lineup.hoverPeekRows == ["a", "b", "c", "d"])                      // at most 4 rows
    let single = arbiter.lineup(ranked, on: filter(), satellite: false)
    #expect(single.satellite == nil && single.overflow.first == "b")          // satellite off: it waits in the peek
    let one = arbiter.lineup(Array(ranked.prefix(1)), on: filter(), satellite: true)
    #expect(one == Lineup(primary: "a", satellite: nil, overflow: [], primarySlot: .short))
}

// MARK: - Per display (step 5, §4.9)

@Test func alertsTheHUDAndTheFlashFollowTheirDisplay() {
    var arbiter = ActivityArbiter()
    let ranked = arbiter.update([activity("hud", .hud, index: 0), activity(.flash, .alert, index: 1),
                                 activity("battery", .alert, index: 2), activity("media", index: 3)],
                                settings: ArbiterSettings(), now: t0).ranked
    let pointer = arbiter.lineup(ranked, on: filter(pointer: true, flash: there), satellite: true)
    #expect(pointer.primary == "hud" && pointer.satellite == "battery" && !pointer.contains(.flash))
    let other = arbiter.lineup(ranked, on: filter(there, pointer: false, flash: there), satellite: true)
    #expect(other.primary == .flash && other.satellite == "media")            // compact shows everywhere
    let restricted = arbiter.lineup(ranked, on: filter(restricted: true), satellite: true)
    #expect(restricted.primary == "hud" && !restricted.contains("media"))     // `.alertsAndHUD`: P0/P1 only
    let quiet = arbiter.lineup(ranked, on: filter(activities: false), satellite: true)
    #expect(quiet.primary == "hud" && quiet.satellite == nil)                  // per-display toggle keeps the HUD
    let noHUD = arbiter.lineup(ranked, on: filter(hud: false), satellite: true)
    #expect(noHUD.primary == "battery")
}

@Test func theHUDRuleIsTheOneTheLineupApplies() {
    // `showsHUD(on:)` is what the HUD module learns through `SystemEnvironment.canPresentHUD`; it must match the lineup.
    var arbiter = ActivityArbiter()
    let ranked = arbiter.update([activity("hud", .hud)], settings: ArbiterSettings(), now: t0).ranked
    for display in [filter(), filter(hud: false), filter(pointer: false), filter(pointer: false, hud: false),
                    filter(restricted: true), filter(activities: false)] {
        #expect(ActivityArbiter.showsHUD(on: display) == arbiter.lineup(ranked, on: display, satellite: true).contains("hud"))
    }
    #expect(ActivityArbiter.showsHUD(on: filter()))
    #expect(!ActivityArbiter.showsHUD(on: filter(hud: false)))
    #expect(!ActivityArbiter.showsHUD(on: filter(pointer: false)))
}

// MARK: - Peeks, announcements, delights (steps 4 and 7)

@Test func onlyNewRevisionsPeekAndNothingPeeksAtLaunch() {
    var arbiter = ActivityArbiter()
    let launch = [activity("meeting", .alert, index: 0), activity("media", index: 1, peeks: true),
                  activity("timer", index: 2), activity(.flash, .alert, index: 3), activity("hud", .hud, index: 4)]
    let atLaunch = arbiter.update(launch, settings: ArbiterSettings(), now: t0)
    #expect(atLaunch.peeks.isEmpty)
    let changed = launch.map { var a = $0; a.revision += 1; return a }
    let outcome = arbiter.update(changed, settings: ArbiterSettings(), now: t0)
    #expect(outcome.peeks == ["meeting", "media"])                            // alerts and "Peek on change"; never flash/HUD
    #expect(outcome.announcements == ["meeting"])                             // P1 only
    #expect(Set(outcome.changed) == Set(launch.map(\.id)))
    let again = arbiter.update(changed, settings: ArbiterSettings(), now: t0)
    #expect(again.peeks.isEmpty)                                              // once per revision
}

@Test func revisionsOfHiddenActivitiesNeverPeekLater() {
    var arbiter = ActivityArbiter()
    _ = arbiter.update([activity("meeting", .alert, active: false)], settings: ArbiterSettings(), now: t0)
    let quiet = arbiter.update([activity("meeting", .alert, active: false, revision: 2)], settings: ArbiterSettings(), now: t0)
    #expect(quiet.peeks.isEmpty)
    let shown = arbiter.update([activity("meeting", .alert, revision: 2)], settings: ArbiterSettings(), now: t0)
    #expect(shown.peeks.isEmpty)                                               // its revision was already seen
    let paused = arbiter.update([activity("meeting", .alert, revision: 3)], settings: ArbiterSettings(paused: true), now: t0)
    #expect(paused.peeks.isEmpty && paused.announcements.isEmpty)
}

@Test func activitiesNameTheirDelightOnANewRevision() {
    var arbiter = ActivityArbiter()
    _ = arbiter.update([activity("timer.done", .alert, delight: .emberBurst)], settings: ArbiterSettings(), now: t0)
    let outcome = arbiter.update([activity("timer.done", .alert, revision: 2, delight: .emberBurst)],
                                 settings: ArbiterSettings(), now: t0)
    #expect(outcome.delights == ["timer.done"])
}

// MARK: - Dismissal and the satellite swap (§4.4, §4.7)

@Test func aDismissalLastsUntilTheNextRevision() {
    var arbiter = ActivityArbiter()
    _ = arbiter.update([activity("media", revision: 4)], settings: ArbiterSettings(), now: t0)
    arbiter.dismiss("media", revision: 4)
    let hidden = arbiter.update([activity("media", revision: 4)], settings: ArbiterSettings(), now: t0)
    #expect(hidden.ranked.isEmpty)
    let back = arbiter.update([activity("media", revision: 5)], settings: ArbiterSettings(), now: t0)
    #expect(back.ranked.map(\.id) == ["media"])

    var sticky = ActivityArbiter()
    let noUnhide = ArbiterSettings(autoUnhide: false)
    _ = sticky.update([activity("media", revision: 4)], settings: noUnhide, now: t0)
    sticky.dismiss("media", revision: 4)
    let stillHidden = sticky.update([activity("media", revision: 5)], settings: noUnhide, now: t0)
    #expect(stillHidden.ranked.isEmpty)
    _ = sticky.update([activity("media", active: false, revision: 5)], settings: noUnhide, now: t0)   // went away
    let returned = sticky.update([activity("media", revision: 6)], settings: noUnhide, now: t0)
    #expect(returned.ranked.map(\.id) == ["media"])
}

@Test func clickingTheSatelliteSwapsThePairUntilItChanges() {
    var arbiter = ActivityArbiter()
    let pair = [activity("timer", index: 0), activity("media", index: 1)]
    let ranked = arbiter.update(pair, settings: ArbiterSettings(), now: t0).ranked
    arbiter.swapSatellite(primary: "timer", satellite: "media")
    let swapped = arbiter.lineup(ranked, on: filter(), satellite: true)
    #expect(swapped.primary == "media" && swapped.satellite == "timer")
    arbiter.swapSatellite(primary: "media", satellite: "timer")                // click again: back
    #expect(arbiter.lineup(ranked, on: filter(), satellite: true).primary == "timer")
    arbiter.swapSatellite(primary: "timer", satellite: "media")
    _ = arbiter.update([activity("timer", index: 0)], settings: ArbiterSettings(), now: t0)   // the pair broke up
    #expect(arbiter.swap == nil)
}

// MARK: - Peek policy (§4.7)

@Test func autoPeeksPlayOnlyOnThePointersVisibleClosedDisplay() {
    let lineup = Lineup(primary: "meeting")
    func display(_ key: DisplayKey, pointer: Bool, open: Bool = false, hidden: Bool = false, peeks: Bool = true) -> PeekScheduler.Display {
        PeekScheduler.Display(key: key, isPointerDisplay: pointer, isOpen: open, isHidden: hidden, showsPeeks: peeks, lineup: lineup)
    }
    #expect(PeekScheduler.target(for: "meeting", among: [display(there, pointer: false), display(here, pointer: true)], paused: false) == here)
    #expect(PeekScheduler.target(for: "meeting", among: [display(here, pointer: true, open: true)], paused: false) == nil)
    #expect(PeekScheduler.target(for: "meeting", among: [display(here, pointer: true, hidden: true)], paused: false) == nil)
    #expect(PeekScheduler.target(for: "meeting", among: [display(here, pointer: true, peeks: false)], paused: false) == nil)
    #expect(PeekScheduler.target(for: "meeting", among: [display(here, pointer: true)], paused: true) == nil)
    #expect(PeekScheduler.target(for: "media", among: [display(here, pointer: true)], paused: false) == nil)   // not shown there
}

// MARK: - Delight caps (§4.6 step 7, DESIGN.md §5.5)

@Test func oneDelightAtATimeAndNoneUnderTheCaps() {
    var scheduler = DelightScheduler()
    let open = DelightScheduler.Gate()
    let ember = scheduler.request(.emberBurst, now: 10, gate: open)
    let early = scheduler.request(.gulp, now: 10.5, gate: open)                // the ember still plays (0.9 s)
    let later = scheduler.request(.gulp, now: 11, gate: open)
    #expect(ember && !early && later)
    // A hidden panel (locked, asleep, hidden by policy) plays nothing and keeps the stage free.
    for gate in [DelightScheduler.Gate(paused: true), .init(fullScreenInFront: true), .init(hidden: true), .init(motion: .calm),
                 .init(motion: .instant), .init(reduceMotion: true)] {
        let allowed = scheduler.request(.songRipple, now: 100, gate: gate)
        #expect(!allowed)
    }
    let afterVetoes = scheduler.request(.songRipple, now: 100, gate: open)
    #expect(afterVetoes)
    let firstOpen = scheduler.firstOpen(), secondOpen = scheduler.firstOpen()
    #expect(firstOpen && !secondOpen)                                          // First light: once per session
}
