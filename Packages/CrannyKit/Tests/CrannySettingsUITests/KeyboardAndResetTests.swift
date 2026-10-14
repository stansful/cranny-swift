import AppKit
import CrannyCore
import Foundation
import Observation
import Testing
@testable import CrannySettingsUI

// MARK: - Shortcut recorder rules

@Test func recorderNeedsACommandModifierExceptForFunctionKeys() {
    let n: UInt16 = 45
    #expect(KeyComboFormatter.outcome(keyCode: n, modifiers: [], character: "n") == .needsModifier)
    #expect(KeyComboFormatter.outcome(keyCode: n, modifiers: [.shift], character: "n") == .needsModifier)
    #expect(KeyComboFormatter.outcome(keyCode: 53, modifiers: [], character: nil) == .cancel)          // Esc
    #expect(KeyComboFormatter.outcome(keyCode: 51, modifiers: [], character: nil) == .clear)           // Delete
    #expect(KeyComboFormatter.outcome(keyCode: 117, modifiers: [], character: nil) == .clear)          // Forward Delete
    #expect(KeyComboFormatter.outcome(keyCode: n, modifiers: [.control, .option], character: "n")
            == .combo(KeyCombo(keyCode: n, modifiers: [.control, .option], display: "⌃⌥N")))
    #expect(KeyComboFormatter.outcome(keyCode: 122, modifiers: [], character: nil)
            == .combo(KeyCombo(keyCode: 122, modifiers: [], display: "F1")))
    #expect(KeyComboFormatter.outcome(keyCode: 53, modifiers: [.command], character: nil)
            == .combo(KeyCombo(keyCode: 53, modifiers: [.command], display: "⌘⎋")))
}

@Test func keyCapsUseApplesModifierOrder() {
    #expect(KeyComboFormatter.display(keyCode: 35, modifiers: [.command, .shift, .option, .control], character: "p") == "⌃⌥⇧⌘P")
    #expect(KeyComboFormatter.display(keyCode: 123, modifiers: [.control], character: nil) == "⌃←")
    #expect(KeyComboFormatter.keyName(keyCode: 200, character: nil) == "#200")
    #expect(KeyComboFormatter.modifiers([.command, .capsLock, .function, .shift]) == [.command, .shift])
}

// MARK: - System shortcuts (best effort)

/// The format observed on macOS 27: `parameters` = [ascii, keyCode, NSEvent modifier flags].
private let domain: [String: Any] = [
    "64": ["enabled": false, "value": ["type": "standard", "parameters": [32, 49, 1_048_576]]],            // Spotlight off
    "118": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 18, 262_144]]],          // ⌃1
    "79": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 123, 8_650_752]]],        // fn⌃←
    "163": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 65535, 0]]],             // no key
    "garbage": ["enabled": true],
    "999": "not a dictionary",
]

@Test func systemShortcutsParseTheDomainAndFillDefaults() {
    let shortcuts = SystemShortcuts.enabled(from: domain)
    #expect(!shortcuts.contains { $0.id == 64 })                              // the user turned Spotlight off
    #expect(shortcuts.contains(SystemShortcut(id: 118, keyCode: 18, modifiers: [.control])))
    #expect(shortcuts.contains(SystemShortcut(id: 79, keyCode: 123, modifiers: [.control])))   // Fn ignored
    #expect(!shortcuts.contains { $0.id == 163 })
    #expect(shortcuts.contains { $0.id == 61 })                               // a default the domain does not list
    #expect(SystemShortcuts.enabled(from: nil).count == SystemShortcuts.defaults.count)
}

@Test func conflictsMatchKeysAndModifiersExactly() {
    let shortcuts = SystemShortcuts.enabled(from: [:])
    let spotlight = KeyCombo(keyCode: 49, modifiers: [.command], display: "⌘Space")
    #expect(SystemShortcuts.conflict(for: spotlight, in: shortcuts)?.id == 64)
    #expect(SystemShortcuts.name(of: 64) != nil)
    #expect(SystemShortcuts.conflict(for: .openNookDefault, in: shortcuts) == nil)       // ⌃⌥N is free by design
    #expect(SystemShortcuts.conflict(for: KeyCombo(keyCode: 49, modifiers: [.command, .shift], display: ""), in: shortcuts) == nil)
}

// MARK: - Reset All with Undo (DESIGN.md §11.3, ARCHITECTURE D14)

/// Resets the store like the shell's `AppControl.resetAllSettings()`.
@MainActor @Observable private final class ResettingAppControl: AppControl {
    let settings: SettingsStore
    var loginItem: LoginItemState = .disabled
    var update: UpdateState = .idle
    private(set) var resets = 0
    init(settings: SettingsStore) { self.settings = settings }
    func setLaunchAtLogin(_ enabled: Bool) {}
    func checkForUpdates() {}
    func shortcutState(_ id: ShortcutID) -> ShortcutState { .off }
    func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { .off }
    func openSettings(_ page: SettingsPageID?) {}
    func showWelcome() {}
    func startTutorial() {}
    func showOnNotch(_ state: PreviewStageState) {}
    func resetAllSettings() { resets += 1; settings.resetAll() }
    func quit() {}
}

@Test func resetAllCanBeUndone() {
    let settings = CrannyServices.preview().settings
    let app = ResettingAppControl(settings: settings)
    settings[CoreSettings.density] = .roomy
    settings[CoreSettings.pages] = [NookPreset.maker.page]
    let controller = ResetAllController(settings: settings, app: app, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    controller.resetAll()
    #expect(app.resets == 1 && controller.canUndo)
    #expect(settings[CoreSettings.density] == .standard && settings[CoreSettings.pages] == [NookPreset.listener.page])
    controller.undo()
    #expect(!controller.canUndo)
    #expect(settings[CoreSettings.density] == .roomy && settings[CoreSettings.pages] == [NookPreset.maker.page])
    controller.undo()                                                          // nothing left to undo
    #expect(settings[CoreSettings.density] == .roomy)
}

@Test func undoExpiresAfterItsWindow() async {
    let settings = CrannyServices.preview().settings
    let app = ResettingAppControl(settings: settings)
    settings[CoreSettings.motion] = .calm
    let controller = ResetAllController(settings: settings, app: app, undoWindow: .milliseconds(1), sleep: { _ in })
    controller.resetAll()
    #expect(controller.canUndo)
    for _ in 0..<50 where controller.canUndo { await Task.yield() }
    #expect(!controller.canUndo)
    controller.undo()
    #expect(settings[CoreSettings.motion] == .standard)                        // the reset stays
}
