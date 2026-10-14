import AppKit
import CrannyCore
import CrannyNotchUI
import Observation
import Testing
@testable import CrannyAppShell

// State machine, view model, arbitration and overlay tests: NotchMachineTests.swift, NotchViewModelTests.swift,
// ActivityArbiterTests.swift and OverlayGeometryTests.swift.

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
    #expect(registry.shortcuts.map(\.id) == [.openNook, .togglePin, .pauseActivities])                 // the shell adds Pause
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

@Test func flashActivityShowsAndExpires() async throws {
    let flash = FlashActivity()
    flash.show(symbol: "hand.wave.fill", label: "Hi", duration: 0.05)
    #expect(flash.isActive && flash.revision == 1 && flash.slot == .medium)
    // The expiry runs on the main actor, which other tests share (creating the first window can take a while).
    for _ in 0..<60 where flash.isActive { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!flash.isActive)
    flash.show(symbol: "pause.fill", label: "Resumed", duration: 5)          // measured: wider than the medium wing
    #expect(flash.slot == .wide && flash.showsLabelInWings && flash.revision == 2)
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
