// The shell's contributions — the Pause shortcut and the ⌘K provider (ARCHITECTURE.md §10.0).
import CrannyCore
import Foundation
import Observation
import SwiftUI
import Testing
@testable import CrannyAppShell

/// Records the `AppControl` calls the palette makes.
@MainActor @Observable private final class RecordingAppControl: AppControl {
    var calls: [String] = []
    var loginItem: LoginItemState = .disabled
    var update: UpdateState = .idle
    func setLaunchAtLogin(_ enabled: Bool) {}
    func checkForUpdates() {}
    func shortcutState(_ id: ShortcutID) -> ShortcutState { .off }
    func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { .off }
    func openSettings(_ page: SettingsPageID?) { calls.append("settings(\(page?.rawValue ?? "-"))") }
    func showWelcome() {}
    func startTutorial() { calls.append("tutorial") }
    func showOnNotch(_ state: PreviewStageState) {}
    func resetAllSettings() {}
    func quit() {}
}

@MainActor private func makeRegistry() -> (ModuleRegistry, RecordingAppControl, OverlayCoordinator) {
    let preview = CrannyServices.preview()
    let app = RecordingAppControl()
    let services = CrannyServices(settings: preview.settings, permissions: preview.permissions, haptics: preview.haptics,
                                  paths: preview.paths, notch: preview.notch, environment: preview.environment, app: app)
    let registry = ModuleRegistry(services: services)
    registry.add(settingsPage: SettingsPage(id: .hud, title: "HUD", symbol: "speaker.wave.2.fill", tint: .teal, group: .notch, order: 2,
                                            keywords: ["volume", "brightness"]) { AnyView(EmptyView()) })
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    ShellContributions.register(in: registry, overlay: overlay)
    return (registry, app, overlay)
}

@MainActor private func palette(_ registry: ModuleRegistry) throws -> any PaletteCommandProvider {
    try #require(registry.commandProviders.first { $0 is ShellCommands })
}

@Test func theShellContributesThreeShortcutsAndOnePalette() throws {
    let (registry, _, _) = makeRegistry()
    #expect(registry.shortcuts.map(\.id) == [.openNook, .togglePin, .pauseActivities])
    #expect(registry.shortcuts.map(\.defaultCombo) == [.openNookDefault, nil, nil])   // Pause is off until bound
    #expect(registry.commandProviders.count == 1)
    _ = try palette(registry)
}

@Test func thePauseShortcutPausesForAnHourOrResumes() throws {
    let (registry, _, _) = makeRegistry()
    let settings = registry.services.settings
    let shortcut = try #require(registry.shortcuts.first { $0.id == .pauseActivities })
    shortcut.perform()
    let until = try #require(settings[CoreSettings.pausedUntil])
    #expect(abs(until.timeIntervalSinceNow - 3600) < 5)
    shortcut.perform()
    #expect(settings[CoreSettings.pausedUntil] == nil)
}

@Test func anEmptyQueryListsTheActionsThatFitTheState() throws {
    let (registry, app, overlay) = makeRegistry()
    let commands = try palette(registry)
    #expect(commands.commands(matching: "").map(\.id) == ["shell.pause", "shell.demo", "shell.pin", "shell.tutorial"])

    try #require(commands.commands(matching: "").first).perform()                    // pause for an hour
    #expect(registry.services.settings[CoreSettings.pausedUntil] != nil)
    #expect(commands.commands(matching: "").first?.id == "shell.resume")
    try #require(commands.commands(matching: "").first).perform()
    #expect(registry.services.settings[CoreSettings.pausedUntil] == nil)

    let demo = try #require(commands.commands(matching: "").first { $0.id == "shell.demo" })
    demo.perform()
    #expect(registry.services.settings[CoreSettings.demoMode])
    #expect(commands.commands(matching: "").first { $0.id == "shell.demo" }?.title != demo.title)   // now "Turn off"

    let pin = try #require(commands.commands(matching: "").first { $0.id == "shell.pin" })
    #expect(pin.shortcut?.display == "⌘P" && pin.symbol == "pin")
    pin.perform()                    // no panel on screen in this test: the coordinator has nothing to pin
    #expect(!overlay.isPinned)
    overlay.isPinned = true          // what an open panel's `.pinned(true)` event sets
    #expect(commands.commands(matching: "").first { $0.id == "shell.pin" }?.symbol == "pin.fill")

    try #require(commands.commands(matching: "").first { $0.id == "shell.tutorial" }).perform()
    #expect(app.calls == ["tutorial"])
}

@Test func typingAlsoFindsEverySettingsPaneInSidebarOrder() throws {
    let (registry, app, _) = makeRegistry()
    let commands = try palette(registry)
    // A module pane is found by its own keywords; its kind ("Settings", localized) then finds every pane.
    let settingsKind = try #require(commands.commands(matching: "volume").first?.kind)
    let panes = commands.commands(matching: settingsKind)
    #expect(panes.map(\.id.rawValue) == ["shell.settings.general", "shell.settings.appearance", "shell.settings.keyboard",
                                          "shell.settings.nook", "shell.settings.activities", "shell.settings.hud",
                                          "shell.settings.gestures", "shell.settings.permissions", "shell.settings.about"])
    let hud = try #require(commands.commands(matching: "volume").first)
    #expect(hud.id == "shell.settings.hud")
    hud.perform()
    #expect(app.calls == ["settings(hud)"])
}

@Test func everyWordOfTheQueryMustMatch() {
    let command = PaletteCommand(id: "x", title: "Turn on demo mode", kind: "Cranny", symbol: "sparkles", keywords: ["presentation"]) {}
    #expect(ShellCommands.matches(command, tokens: ShellCommands.tokens("demo")))
    #expect(ShellCommands.matches(command, tokens: ShellCommands.tokens("  DEMO   Présentation ")))      // case and accents
    #expect(!ShellCommands.matches(command, tokens: ShellCommands.tokens("demo hour")))
    #expect(ShellCommands.tokens("   ").isEmpty)
    #expect(ShellPane.split(" a, b ,, c ") == ["a", "b", "c"])
}
