import AppKit
import CrannyCore
import CrannyNotchUI
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
    #expect(registry.shortcuts.map(\.id) == [.openNook, .togglePin])
    #expect(registry.shortcuts.first?.defaultCombo == .openNookDefault)
    #expect(registry.activity(.flash)?.kind.defaultPriority == .alert)
    #expect(registry.activity(.flash)?.activity.isActive == false)
}

@Test func flashActivityShowsAndExpires() async throws {
    let flash = FlashActivity()
    flash.show(symbol: "hand.wave.fill", label: "Hi", duration: 0.05)
    #expect(flash.isActive && flash.revision == 1 && flash.slot == .medium)
    try await Task.sleep(for: .milliseconds(300))
    #expect(!flash.isActive)
    flash.show(symbol: "doc.on.doc", label: "Path copied", duration: 5)
    #expect(flash.slot == .wide && flash.revision == 2)
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
