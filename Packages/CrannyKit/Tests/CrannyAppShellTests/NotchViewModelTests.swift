// The view model between the reducer and the scene (ARCHITECTURE.md §4, §4.12): lineups into the scene, clicks on
// activities open their widget's page, swipes reach the activity, effects run (one sleep per timer), and the
// "Show on Notch" override. Uses `CrannyServices.preview()` and a probe activity; no windows.
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation
import SwiftUI
import Testing
@testable import CrannyAppShell

@MainActor @Observable private final class ProbeActivity: LiveActivity {
    let id: ActivityID
    var isActive = true
    var priority: ActivityPriority = .ongoing
    var slot: SlotWidth = .medium
    var revision = 1
    var opensWidget: WidgetID? = .timer
    var accessibilityLabel: String { "Probe" }
    private(set) var gestures: [ActivityGesture] = []

    init(id: ActivityID) { self.id = id }
    func handle(_ gesture: ActivityGesture) -> Bool { gestures.append(gesture); return true }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

private struct Fixture {
    let registry: ModuleRegistry
    let viewModel: NotchViewModel
    let probe: ProbeActivity
    var scene: NotchSceneModel { viewModel.scene }
    var settings: SettingsStore { registry.services.settings }

    @MainActor init(metrics: NotchMetrics = .reference) {
        registry = ModuleRegistry(services: .preview())
        probe = ProbeActivity(id: "probe.one")
        registry.add(activity: probe, kind: ActivityKind(id: "probe.one", module: "probe", title: "Probe", symbol: "timer",
                                                         defaultPriority: .ongoing))
        viewModel = NotchViewModel(scene: NotchSceneModel(layout: NotchLayout(metrics: metrics), theme: CrannyTheme()),
                                   registry: registry)
        viewModel.pointerKeys = { (false, false) }                              // never the real mouse or keyboard
    }
}

/// Waits (real time) until `condition` holds or `seconds` pass. Generous: the first AppKit use in the test process
/// can block the main actor for a couple of seconds while other tests start.
@MainActor private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while !condition(), ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(for: .milliseconds(10)) }
}

@Test func theLineupBecomesTheScenesCompactAndPeekRows() {
    let f = Fixture()
    f.viewModel.setLineup(Lineup(primary: "probe.one", satellite: "probe.two", overflow: ["probe.three"], primarySlot: .medium))
    #expect(f.scene.phase == .compact && f.scene.primary == "probe.one" && f.scene.satellite == "probe.two")
    #expect(f.scene.primarySlot == .medium && f.scene.peekRows.isEmpty)
    f.viewModel.send(.pointerEntered)
    f.viewModel.send(.dwellElapsed(shouldOpen: true))
    #expect(f.scene.phase == .peek && f.scene.peekRows == ["probe.one", "probe.two", "probe.three"])
    f.viewModel.send(.close)
    f.viewModel.send(.autoPeek("probe.two", until: .infinity))
    #expect(f.scene.peekRows == ["probe.two"])
}

/// Peek row / compact click: open the Nook focused on that activity's widget, on the page that holds it (§4.4).
@Test func clickingAnActivityOpensItsWidgetsPage() {
    let f = Fixture()
    f.settings[CoreSettings.pages] = [NookPreset.listener.page,
                                      NookPage(id: "page.focus", symbol: "note.text", items: [.init(.timer, cells: 2)])]
    f.viewModel.actions.activityTapped("probe.one")
    #expect(f.scene.open == OpenState(page: "page.focus", focus: .timer, reason: .click))
    #expect(f.scene.context.focusedWidget == .timer && f.scene.context.page == "page.focus")
    f.viewModel.send(.close)
    f.viewModel.setLineup(Lineup(primary: "probe.one"))
    f.viewModel.send(.click)                                                    // a click on the compact wings
    #expect(f.scene.open?.focus == .timer && f.scene.open?.page == "page.focus")
}

@Test func swipesReachTheActivityAndTheArbiter() {
    var f = Fixture()
    var dismissed: [ActivityID] = []
    f.viewModel.dismissActivity = { dismissed.append($0) }
    f.viewModel.setLineup(Lineup(primary: "probe.one"))
    f.viewModel.send(.swipe(.right, target: .shape))
    #expect(f.probe.gestures == [.swipeRight])
    f.viewModel.send(.swipe(.up, target: .shape))
    #expect(dismissed == ["probe.one"])
    f = Fixture()
    f.viewModel.setGestureTranslation(CGSize(width: 0, height: 12))
    #expect(f.scene.gestureTranslation.height == 12)
}

@Test func showOnNotchOverridesTheArbiterUntilCleared() {
    let f = Fixture()
    f.viewModel.setLineup(Lineup(primary: "probe.one"))
    f.viewModel.overrideLineup(Lineup(primary: "sample.media", primarySlot: .short))
    f.viewModel.setLineup(Lineup(primary: "probe.other"))                       // the arbiter keeps working meanwhile
    #expect(f.scene.primary == "sample.media")
    f.viewModel.overrideLineup(nil)
    #expect(f.scene.primary == "probe.other")
}

@Test func hiddenPanelsHaveNoHoverZonesExceptTheIdleHandle() {
    let f = Fixture(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920))
    #expect(f.viewModel.hoverGeometry == f.scene.layout.closed)
    f.viewModel.send(.swipe(.up, target: .shape))                               // hide the handle
    #expect(f.scene.phase == .hidden && f.viewModel.hoverGeometry == f.scene.layout.closed)
    var locked = NotchEnvironment()
    locked.isLocked = true
    f.viewModel.setEnvironment(locked)
    #expect(f.viewModel.hoverGeometry == nil)
}

@Test func theSceneCarriesContextFlagsAndDelights() {
    let f = Fixture()
    var events: [NotchEvent] = []
    f.viewModel.onEvent = { events.append($0) }
    f.viewModel.send(.hotKey)
    #expect(f.scene.context.keyboardNavigation)                                 // opened by keyboard: focus rings on
    f.viewModel.setCommandHints(true)
    f.viewModel.setCommandHints(true)
    #expect(f.scene.context.showsCommandHints && events.filter { $0 == .commandHintsShown }.count == 1)
    f.viewModel.send(.close)
    #expect(!f.scene.context.showsCommandHints)
    f.viewModel.playDelight(.gulp)
    f.viewModel.playDelight(.gulp)
    #expect(f.scene.delight == .gulp && f.scene.delightSerial == 2)
    var demo = NotchEnvironment()
    demo.demoMode = true
    f.viewModel.setEnvironment(demo)
    #expect(f.scene.context.redactsPersonalData)                                // Demo mode + "Redact calendar titles"
    let pages = [NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: [.init(.timer, cells: 2)])]
    f.viewModel.actions.commitLayout(pages)                                     // ⌘E writes through the owner
    #expect(f.settings[CoreSettings.pages] == pages)
}

/// `makeKey` posts didBecomeKey synchronously, so the key hold arrives while the hot key is being reduced.
@Test func inputsFedBackByEffectsAreReducedInOrder() {
    let f = Fixture()
    var events: [NotchEvent] = []
    f.viewModel.makeKey = { f.viewModel.send(.hold(NotchMachineState.typingHold, true)) }
    f.viewModel.onEvent = { events.append($0) }
    f.viewModel.send(.hotKey)
    #expect(f.viewModel.state.isOpen && f.viewModel.state.holds == [NotchMachineState.typingHold])
    #expect(events == [.opened(.keyboard)])
    f.viewModel.send(.pointerEntered)
    f.viewModel.send(.pointerLeft)
    #expect(!f.viewModel.state.timers.contains(.grace))
}

/// A page that is not there (module not registered, user page deleted) never opens: no tab would be selected
/// and the light would sit behind a bare placeholder.
@Test func onlyExistingPagesOpen() {
    let f = Fixture()
    f.viewModel.send(.open(page: .tray, focus: nil, reason: .programmatic))     // no Tray module registered
    #expect(f.viewModel.state.surface == .open(OpenState(page: .nook, reason: .programmatic)))
    f.viewModel.send(.selectPage("page.gone"))
    #expect(f.scene.open?.page == .nook && f.settings[CoreSettings.lastPage] == .nook)
    f.viewModel.send(.close)
    f.settings[CoreSettings.lastPage] = "page.deleted"                          // stale persisted value
    f.viewModel.send(.hotKey)
    #expect(f.scene.open?.page == .nook)
}

/// The effects really run: the dwell is one sleep, then the panel opens (hover delay Instant).
@Test func theDwellTimerFiresAndOpens() async throws {
    let f = Fixture()
    f.settings[CoreSettings.hoverDelay] = .instant
    f.viewModel.send(.pointerEntered)
    #expect(f.scene.phase == .breath)
    for _ in 0..<60 where f.scene.phase != .open { try await Task.sleep(for: .milliseconds(50)) }
    #expect(f.scene.phase == .open && f.scene.open?.reason == .hover)
}

/// Quick peek over compact dwells 0.18 s whatever the hover delay (DESIGN.md §4.6): a Long delay (0.45 s) must not
/// turn every quick peek into "passing through".
@Test(arguments: HoverIntent.Delay.allCases)
func quickPeekOnHoverWorksForEveryHoverDelay(_ delay: HoverIntent.Delay) async throws {
    let f = Fixture()
    f.settings[CoreSettings.hoverDelay] = delay
    f.viewModel.setLineup(Lineup(primary: "probe.one"))
    f.viewModel.send(.pointerEntered)
    try await waitUntil(10) { f.scene.phase == .peek }
    #expect(f.scene.phase == .peek && f.viewModel.state.hover == .inside, "hover delay \(delay): \(f.viewModel.state) \(f.scene.phase)")
}

/// A full-screen Space found when the dwell fires extends it to 0.40 s from entry (one window-list query per
/// hover, not per retry), then it opens.
@Test func aFullScreenSpaceFoundAtTheDwellExtendsIt() async throws {
    let f = Fixture()
    f.settings[CoreSettings.hoverDelay] = .short
    var checks = 0
    f.viewModel.refreshEnvironment = {
        checks += 1
        var environment = NotchEnvironment()
        environment.fullScreen = true                                          // `.alertsAndHUD`
        return environment
    }
    let start = ProcessInfo.processInfo.systemUptime
    f.viewModel.send(.pointerEntered)
    try await waitUntil(10) { f.scene.phase == .open }
    #expect(f.scene.phase == .open && ProcessInfo.processInfo.systemUptime - start >= HoverIntent.fullScreenDwell - 0.01)
    #expect(checks == 1)
}

/// A pointer that rests on the notch after arriving fast opens; while it is too fast the dwell looks again every
/// 50 ms at most (Instant used to spin on 0-s sleeps), with one full-screen check for the whole hover.
@Test func aFastPointerIsRetriedWithAFloor() async throws {
    let f = Fixture()
    f.settings[CoreSettings.hoverDelay] = .instant
    var checks = 0, speedReads = 0
    f.viewModel.refreshEnvironment = { checks += 1; return nil }
    let start = ProcessInfo.processInfo.systemUptime
    f.viewModel.pointerSpeed = {
        speedReads += 1
        return ProcessInfo.processInfo.systemUptime - start < 0.25 ? 5000 : 0
    }
    f.viewModel.send(.pointerEntered)
    try await waitUntil(10) { f.scene.phase == .open }
    #expect(f.scene.phase == .open && checks == 1)
    #expect(speedReads < 40, "\(speedReads) speed reads in 0.25 s")
}
