// The coordinator's glue without panels (ARCHITECTURE.md §4.6, §4.8–§4.9): what it snapshots for the arbiter,
// the per-display environment it derives from settings and the pointer, and dismissals. No windows are created
// (`start()` is never called), so this runs everywhere.
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI
import Testing
@testable import CrannyAppShell

@MainActor @Observable private final class StubActivity: LiveActivity {
    let id: ActivityID
    var isActive = true
    var priority: ActivityPriority = .ongoing
    var slot: SlotWidth = .short
    var revision = 3
    var delight: DelightMoment? = .emberBurst
    var accessibilityLabel: String { "Stub" }
    init(id: ActivityID) { self.id = id }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

@MainActor private func makeOverlay() -> (OverlayCoordinator, ModuleRegistry, StubActivity) {
    let registry = ModuleRegistry(services: .preview())
    let stub = StubActivity(id: "stub.one")
    registry.add(activity: stub, kind: ActivityKind(id: "stub.one", module: "stub", title: "Stub", symbol: "timer",
                                                     defaultPriority: .ongoing, canPeekOnChange: true))
    return (OverlayCoordinator(registry: registry, environment: ShellEnvironment()), registry, stub)
}

@Test func theArbiterSeesEveryActivityWithItsPreferences() throws {
    let (overlay, registry, _) = makeOverlay()
    var input = try #require(overlay.arbitrationInput())
    #expect(input.activities.map(\.id) == ["stub.one", .flash])                 // registration order; the shell's flash last
    let stub = try #require(input.activities.first)
    #expect(stub.isEnabled && !stub.peeksOnChange && stub.revision == 3 && stub.delight == .emberBurst)
    registry.services.settings[CoreSettings.activityPreferences] = ["stub.one": ActivityPreference(isEnabled: false, peeksOnChange: true)]
    registry.services.settings[CoreSettings.activityOrder] = ["stub.one"]
    input = try #require(overlay.arbitrationInput())
    #expect(!input.activities[0].isEnabled && input.activities[0].peeksOnChange && input.settings.order == ["stub.one"])
}

@Test func theEnvironmentOfADisplayFollowsThePolicyAndThePointer() {
    let (overlay, registry, _) = makeOverlay()
    let settings = registry.services.settings
    settings[CoreSettings.fullScreenPolicy] = .hideAll
    overlay.pointerDisplay = "display-a"
    #expect(overlay.environmentFacts(for: "display-b").policy == .hideAll)
    #expect(!overlay.environmentFacts(for: "display-b").notThisDisplay)          // `.builtIn`: no pointer following
    settings[CoreSettings.displaySelection] = .pointer
    #expect(overlay.environmentFacts(for: "display-b").notThisDisplay)
    #expect(!overlay.environmentFacts(for: "display-a").notThisDisplay)
    var restricted = DisplayPreferences()
    restricted.showsActivities = false
    settings[CoreSettings.perDisplay] = ["display-a": restricted]
    #expect(!overlay.displayFilter(for: "display-a").showsActivities)
}

@Test func aDismissalHidesTheActivityUntilItChanges() throws {
    let (overlay, _, stub) = makeOverlay()
    overlay.arbitrate(try #require(overlay.arbitrationInput()))
    #expect(overlay.ranked.map(\.id) == ["stub.one"])
    overlay.dismiss("stub.one")
    #expect(overlay.ranked.isEmpty)
    stub.revision += 1                                                          // a meaningful change: auto-unhide
    overlay.arbitrate(try #require(overlay.arbitrationInput()))
    #expect(overlay.ranked.map(\.id) == ["stub.one"])
}

// MARK: - Whether a HUD would be drawn (`SystemEnvironment.canPresentHUD`)

@Test func withoutAPanelNoHUDCanBeDrawn() {
    // Every chosen display is style Off: no panel, so the HUD must leave the keys to macOS.
    let environment = ShellEnvironment()
    let overlay = OverlayCoordinator(registry: ModuleRegistry(services: .preview()), environment: environment)
    #expect(overlay.alertController == nil)
    #expect(environment.canPresentHUD)                                          // nothing decided yet
    #expect(!overlay.canPresentHUD())
    overlay.applyDisplayFacts()
    #expect(!environment.canPresentHUD)
}

@Test func theHUDIsDrawnOnlyWhereItsDisplayShowsIt() {
    let here = DisplayKey(rawValue: "display-here")
    let pointer = DisplayFilter(key: here, isPointerDisplay: true)
    let visible = NotchEnvironment()
    #expect(OverlayCoordinator.canPresentHUD(filter: pointer, environment: visible))
    var hudOff = pointer
    hudOff.showsHUD = false                                                     // General ▸ Displays ▸ HUD off
    #expect(!OverlayCoordinator.canPresentHUD(filter: hudOff, environment: visible))
    var otherDisplay = pointer
    otherDisplay.isPointerDisplay = false
    #expect(!OverlayCoordinator.canPresentHUD(filter: otherDisplay, environment: visible))
    var quiet = pointer
    quiet.showsActivities = false                                               // the per-display toggle keeps the HUD
    #expect(OverlayCoordinator.canPresentHUD(filter: quiet, environment: visible))

    // A hidden panel draws nothing: the `.pointer` selection with the pointer on a display without a panel
    // (the HUD falls back to the primary display), lock, sleep, "Hide everything" behind a full-screen app.
    #expect(!OverlayCoordinator.canPresentHUD(filter: pointer, environment: NotchEnvironment(notThisDisplay: true)))
    #expect(!OverlayCoordinator.canPresentHUD(filter: pointer, environment: NotchEnvironment(isLocked: true)))
    #expect(!OverlayCoordinator.canPresentHUD(filter: pointer, environment: NotchEnvironment(displaysAsleep: true)))
    #expect(!OverlayCoordinator.canPresentHUD(filter: pointer, environment: NotchEnvironment(fullScreen: true, policy: .hideAll)))
    #expect(OverlayCoordinator.canPresentHUD(filter: pointer, environment: NotchEnvironment(fullScreen: true, policy: .alertsAndHUD)))
}
