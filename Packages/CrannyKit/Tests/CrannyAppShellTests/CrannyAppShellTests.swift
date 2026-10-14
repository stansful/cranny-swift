import AppKit
import CrannyCore
import CrannyNotchUI
import Observation
import Testing
@testable import CrannyAppShell

// MARK: - State machine (ARCHITECTURE.md §4.4 rows implemented by WP0)

private let config = NotchMachineConfig()

private func run(_ inputs: [NotchInput], from start: NotchMachineState = NotchMachineState(),
                 config: NotchMachineConfig = config) -> (NotchMachineState, [NotchEffect]) {
    var state = start
    var effects: [NotchEffect] = []
    for (i, input) in inputs.enumerated() {
        let (next, fx) = NotchMachine.reduce(state, input, now: Double(i), config: config)
        state = next
        effects += fx
    }
    return (state, effects)
}

@Test func hoverDwellOpensTheConfiguredPage() {
    var c = config
    c.lastPage = "page.focus"
    let (dwelling, fx1) = run([.pointerEntered], config: c)
    #expect(fx1 == [.scheduleDwell(HoverIntent.defaultDelay.seconds)])
    #expect(NotchMachine.phase(dwelling, config: c) == .breath)                 // the breath acknowledges the dwell
    let (open, fx2) = run([.dwellElapsed(shouldOpen: true)], from: dwelling, config: c)
    #expect(open.surface == .open(OpenState(page: "page.focus", reason: .hover)))
    #expect(fx2.contains(.emit(.opened(.hover))))
    #expect(!fx2.contains(.makeKey))                                            // hover never takes keyboard focus
    #expect(NotchMachine.phase(open, config: c) == .open)
}

@Test func passingThroughDoesNotOpen() {
    let (s, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: false)])
    #expect(s.isClosed && s.hover == .inside)
    let (left, fx) = run([.pointerEntered, .pointerLeft])
    #expect(left.hover == .outside && fx.last == .cancelDwell)
}

@Test func leavingClosesAfterGraceUnlessReentered() {
    let (open, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)])
    let (leaving, fx) = run([.pointerLeft], from: open)
    #expect(fx == [.scheduleGrace(HoverIntent.closeGrace)] && leaving.graceDeadline != nil)
    let (back, fxBack) = run([.pointerEntered, .graceElapsed], from: leaving)
    #expect(back.isOpen && fxBack.first == .cancelGrace)                        // re-entering cancels the close
    let (closed, fxClosed) = run([.graceElapsed], from: leaving)
    #expect(closed.isClosed)
    #expect(fxClosed.contains(.relinquishKey) && fxClosed.contains(.emit(.closed)))
}

@Test func pinsAndHoldsKeepItOpen() {
    let (open, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)])
    let (pinned, fx) = run([.setPinned(true), .pointerLeft], from: open)
    #expect(pinned.isOpen && pinned.graceDeadline == nil && fx == [.emit(.pinned(true))])
    let (unpinned, fx2) = run([.setPinned(false)], from: pinned)
    #expect(fx2.contains(.scheduleGrace(HoverIntent.closeGrace)) && unpinned.graceDeadline != nil)
    let (held, _) = run([.hold("notes.editing", true), .pointerLeft], from: open)
    #expect(held.graceDeadline == nil)
    let (released, _) = run([.hold("notes.editing", false), .graceElapsed], from: held)
    #expect(released.isClosed)
    var c = config
    c.closeOnLeave = false
    let (stays, _) = run([.pointerLeft, .graceElapsed], from: open, config: c)
    #expect(stays.isOpen)
}

/// §4.4 "pointer leaves exit zone → grace → closed" requires "panel not key"; §4.5 lists "panel is key (typing)"
/// and a tracking menu as holds.
@Test func aKeyPanelOrATrackingMenuIsNotClosedByLeaving() {
    let typing = NotchMachineState.typingHold
    let (open, _) = run([.hotKey, .hold(typing, true)])
    let (crossed, fx) = run([.pointerEntered, .pointerLeft, .graceElapsed], from: open)
    #expect(crossed.isOpen && crossed.graceDeadline == nil)
    #expect(!fx.contains(.scheduleGrace(HoverIntent.closeGrace)) && !fx.contains(.relinquishKey))
    let (resigned, fx2) = run([.hold(typing, false)], from: crossed)                // clicked elsewhere: key is gone
    #expect(fx2 == [.scheduleGrace(HoverIntent.closeGrace)] && resigned.isOpen)
    let (closed, _) = run([.graceElapsed], from: resigned)
    #expect(closed.isClosed)

    let (hovered, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true), .hold(NotchMachineState.menuHold, true)])
    let (menu, fx3) = run([.pointerLeft, .graceElapsed], from: hovered)
    #expect(menu.isOpen && !fx3.contains(.scheduleGrace(HoverIntent.closeGrace)))
    let (menuClosed, _) = run([.hold(NotchMachineState.menuHold, false), .graceElapsed], from: menu)
    #expect(menuClosed.isClosed)
}

/// `makeKey` posts didBecomeKey synchronously, so the key hold arrives while the hot key is being reduced.
@Test func inputsFedBackByEffectsAreReducedInOrder() {
    let registry = ModuleRegistry(services: .preview())
    let viewModel = NotchViewModel(scene: NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme()),
                                   registry: registry)
    var events: [NotchEvent] = []
    viewModel.makeKey = { viewModel.send(.hold(NotchMachineState.typingHold, true)) }
    viewModel.onEvent = { events.append($0) }
    viewModel.send(.hotKey)
    #expect(viewModel.state.isOpen && viewModel.state.holds == [NotchMachineState.typingHold])
    #expect(events == [.opened(.keyboard)])
    viewModel.send(.pointerEntered)
    viewModel.send(.pointerLeft)
    #expect(viewModel.state.graceDeadline == nil)
}

/// A page that is not there (module not registered, user page deleted) never opens: no tab would be selected
/// and the light would sit behind a bare placeholder.
@Test func onlyExistingPagesOpen() {
    let registry = ModuleRegistry(services: .preview())
    let viewModel = NotchViewModel(scene: NotchSceneModel(layout: NotchLayout(metrics: .reference), theme: CrannyTheme()),
                                   registry: registry)
    viewModel.send(.open(page: .tray, focus: nil, reason: .programmatic))           // no Tray module registered
    #expect(viewModel.state.surface == .open(OpenState(page: .nook, reason: .programmatic)))
    viewModel.send(.selectPage("page.gone"))
    #expect(viewModel.scene.open?.page == .nook && registry.services.settings[CoreSettings.lastPage] == .nook)
    viewModel.send(.close)
    registry.services.settings[CoreSettings.lastPage] = "page.deleted"                // stale persisted value
    viewModel.send(.hotKey)
    #expect(viewModel.scene.open?.page == .nook)
}

@Test func escapeLeavesModesFirstThenClosesAndHandsFocusBack() {
    let (open, fx) = run([.hotKey])
    #expect(open.surface == .open(OpenState(page: .nook, reason: .keyboard)) && fx.contains(.makeKey))
    let (palette, _) = run([.setMode(.palette)], from: open)
    let (grid, _) = run([.escape], from: palette)
    #expect(grid.surface == .open(OpenState(page: .nook, mode: .grid, reason: .keyboard)))
    let (closed, fx2) = run([.escape], from: grid)
    #expect(closed.isClosed && fx2.contains(.relinquishKey))
    let (toggled, _) = run([.hotKey, .hotKey])
    #expect(toggled.isClosed)
}

@Test func openModesGateHover() {
    var click = config
    click.openMode = .click
    let (breath, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: click)
    #expect(breath.isClosed && NotchMachine.phase(breath, config: click) == .breath)   // breath only …
    let (open, _) = run([.click], from: breath, config: click)
    #expect(open.surface == .open(OpenState(page: .nook, reason: .click)))           // … the click opens
    var shortcutOnly = config
    shortcutOnly.openMode = .shortcutOnly
    let (idle, fx) = run([.pointerEntered], config: shortcutOnly)
    #expect(fx.isEmpty && NotchMachine.phase(idle, config: shortcutOnly) == .idle)
    var voiceOver = config
    voiceOver.voiceOverRunning = true
    let (vo, _) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: voiceOver)
    #expect(vo.isClosed)                                                               // VoiceOver: click or shortcut
}

@Test func compactPeeksOnHoverAndPagesPersist() {
    var c = config
    c.hasPrimaryActivity = true
    let (peek, fx) = run([.pointerEntered, .dwellElapsed(shouldOpen: true)], config: c)
    #expect(fx.first == .scheduleDwell(HoverIntent.peekDwell))
    #expect(peek.surface == .peek(.hover) && NotchMachine.phase(peek, config: c) == .peek)
    let (open, _) = run([.click, .selectPage(.tray)], from: peek, config: c)
    #expect(open.surface == .open(OpenState(page: .tray, reason: .click)))
    #expect(NotchMachine.phase(NotchMachineState(), config: c) == .compact)
}

// MARK: - Hot keys, contributions, menu bar

@Test func hotKeyBindingsResolveAgainstDefaults() {
    let open = GlobalShortcut(id: .openNook, title: "Open", defaultCombo: .openNookDefault) {}
    let pin = GlobalShortcut(id: .togglePin, title: "Pin") {}
    #expect(HotKeyCenter.effectiveCombo(for: open, bindings: [:]) == .openNookDefault)
    #expect(HotKeyCenter.effectiveCombo(for: open, bindings: [.openNook: nil]) == nil)               // explicitly off
    let custom = KeyCombo(keyCode: 31, modifiers: [.command, .shift], display: "⇧⌘O")
    #expect(HotKeyCenter.effectiveCombo(for: open, bindings: [.openNook: custom]) == custom)
    #expect(HotKeyCenter.effectiveCombo(for: pin, bindings: [:]) == nil)                            // off until set
    #expect(HotKeyCenter.carbonModifiers([.control, .option]) == 0x1000 | 0x0800)                    // controlKey | optionKey
    #expect(HotKeyCenter.carbonModifiers([.command, .shift]) == 0x0100 | 0x0200)
}

@Test func shellRegistersItsShortcutsAndFlashActivity() {
    let registry = ModuleRegistry(services: .preview())
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    ShellContributions.register(in: registry, overlay: overlay)
    #expect(registry.shortcuts.map(\.id) == [.openNook, .togglePin, .pauseActivities])                 // WP16 adds Pause
    #expect(registry.shortcuts.first?.defaultCombo == .openNookDefault)
    #expect(registry.activity(.flash)?.kind.defaultPriority == .alert)
    #expect(registry.activity(.flash)?.activity.isActive == false)
}

/// `AppControl.setShortcut` returns the RESULTING state (§3.9), and `shortcutState` is observable for Settings.
@Test func setShortcutReturnsTheResultingStateAndViewsRefresh() throws {
    let registry = ModuleRegistry(services: .preview())
    registry.add(shortcut: GlobalShortcut(id: .togglePin, title: "Pin") {})
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    let control = ShellAppControl()
    control.connect(settings: registry.services.settings, overlay: overlay, settingsWindow: SettingsWindowController(registry: registry),
                    welcomeWindow: WelcomeWindowController(registry: registry), hotKeys: overlay.hotKeys)
    overlay.hotKeys.start(registry: registry)
    defer { overlay.hotKeys.stop() }
    #expect(control.shortcutState(.togglePin) == .off)                                 // no default combo

    nonisolated final class Flag: @unchecked Sendable { var fired = false }              // written on the main actor only
    let flag = Flag()
    withObservationTracking { _ = control.shortcutState(.togglePin) } onChange: { flag.fired = true }
    // ⌃⌥⇧⌘F19: a combination nobody uses, so the test never collides with a real shortcut.
    let combo = KeyCombo(keyCode: 80, modifiers: [.control, .option, .shift, .command], display: "⌃⌥⇧⌘F19")
    #expect(control.setShortcut(.togglePin, combo) == .registered)
    #expect(flag.fired)
    #expect(control.setShortcut(.togglePin, nil) == .off)
    #expect(control.shortcutState(.togglePin) == .off)
}

/// `NotchControl.flash` shows on one display only (§4.9: peeks and alerts on the pointer's display).
@Test func theFlashAppearsOnItsDisplayOnly() {
    typealias Candidate = OverlayCoordinator.Arbitration.Candidate
    let a = DisplayKey(rawValue: "display-a"), b = DisplayKey(rawValue: "display-b")
    let result = OverlayCoordinator.Arbitration(
        ranked: [Candidate(id: .flash, slot: .medium), Candidate(id: "media.nowPlaying", slot: .wide)], flashDisplay: a)
    #expect(result.primary(on: a)?.id == .flash)
    #expect(result.primary(on: b)?.id == "media.nowPlaying")
    #expect(OverlayCoordinator.Arbitration(ranked: [Candidate(id: .flash, slot: .medium)], flashDisplay: nil).primary(on: a) == nil)
}

@Test func flashActivityShowsAndExpires() async throws {
    let flash = FlashActivity()
    flash.show(symbol: "hand.wave.fill", label: "Hi", duration: 0.05)
    #expect(flash.isActive && flash.revision == 1 && flash.slot == .medium)
    // The expiry runs on the main actor, which other tests share (creating the first window can take a while).
    for _ in 0..<60 where flash.isActive { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!flash.isActive)
    flash.show(symbol: "doc.on.doc", label: "Path copied", duration: 5)
    #expect(flash.slot == .wide && flash.revision == 2)
    flash.hide()                                                                       // pause began
    #expect(!flash.isActive && flash.expiresAt == nil)
}

@Test func menuBarIconIsATemplateDrawnInCode() {
    #expect(MenuBarIcon.image.isTemplate)
    #expect(MenuBarIcon.image.size == CGSize(width: 18, height: 14))
}

#if DEBUG
@Test func qaArgumentsParse() {
    let o = QAHooks.Options(arguments: ["Cranny", "--qa-state", "open", "--qa-page", "tray", "--qa-exit-after", "8"])
    #expect(o == QAHooks.Options(state: .open, page: .tray, exitAfter: 8))
    #expect(QAHooks.Options(arguments: ["Cranny"]).isEmpty)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-state", "sideways", "--qa-exit-after", "-1"]).isEmpty)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-state"]).state == nil)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-settings", "about"]).settingsPage == .about)
}
#endif
