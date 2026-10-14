// WP16: the menu bar extra's logic — Show On ▸ (`ShowOnPolicy`, `DisplayList`), key equivalents, the wiring of
// `ShellAppServices` into the `AppControl` port, and the QA launch arguments of the menu.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyAppShell

private let builtIn = ConnectedDisplay(key: "built-in", name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true)
private let studio = ConnectedDisplay(key: "studio", name: "Studio Display", isBuiltIn: false, hasNotch: false)
private let dell = ConnectedDisplay(key: "dell", name: "DELL U2723QE", isBuiltIn: false, hasNotch: false)
private let laptopAndTwo = [builtIn, studio, dell]

private func policy(_ selection: DisplaySelection, _ perDisplay: [DisplayKey: DisplayPreferences] = [:],
                    noNotch: NoNotchStyle = .floatingIsland) -> ShowOnPolicy {
    ShowOnPolicy(selection: selection, perDisplay: perDisplay, noNotchStyle: noNotch)
}

// MARK: - Show On

@Test func showOnChecksTheDisplaysThatGetAPanel() {
    #expect(policy(.builtIn).shownKeys(on: laptopAndTwo) == ["built-in"])
    #expect(policy(.builtIn).shownKeys(on: [studio, dell]) == ["studio"])           // clamshell: the primary display
    #expect(policy(.all).shownKeys(on: laptopAndTwo) == ["built-in", "studio", "dell"])
    #expect(policy(.custom(["dell"])).shownKeys(on: laptopAndTwo) == ["dell"])
    #expect(policy(.custom(["gone"])).shownKeys(on: laptopAndTwo) == ["built-in"])  // nothing chosen is connected
    // A display without a notch whose style is Off gets no panel, so it is not checked.
    #expect(policy(.all, ["studio": DisplayPreferences(style: .off)]).shownKeys(on: laptopAndTwo) == ["built-in", "dell"])
    #expect(policy(.all, noNotch: .off).shownKeys(on: laptopAndTwo) == ["built-in"])
}

@Test func clickingDisplaysWritesTheSimplestSelection() {
    let added = policy(.builtIn).toggling("studio", on: laptopAndTwo)
    #expect(added.selection == .custom(["built-in", "studio"]))
    let all = added.toggling("dell", on: laptopAndTwo)
    #expect(all.selection == .all)
    let removed = all.toggling("built-in", on: laptopAndTwo)
    #expect(removed.selection == .custom(["studio", "dell"]))
    let back = policy(.custom(["built-in", "dell"])).toggling("dell", on: laptopAndTwo)
    #expect(back.selection == .builtIn)                                             // the default again
}

@Test func theLastDisplayCannotBeUnchecked() {
    let only = policy(.builtIn)
    #expect(!only.canToggle("built-in", on: laptopAndTwo) && only.canToggle("studio", on: laptopAndTwo))
    #expect(only.toggling("built-in", on: laptopAndTwo) == only)
    #expect(!policy(.all).canToggle("built-in", on: [builtIn]))                    // one display: always on
}

@Test func checkingADisplayStyledOffShowsAnIsland() {
    let off = policy(.all, ["studio": DisplayPreferences(style: .off)])
    let on = off.toggling("studio", on: laptopAndTwo)
    #expect(on.selection == .all && on.perDisplay["studio"]?.style == .floatingIsland)
    #expect(on.shownKeys(on: laptopAndTwo).contains("studio"))
    let globalOff = policy(.builtIn, noNotch: .off).toggling("dell", on: laptopAndTwo)
    #expect(globalOff.perDisplay["dell"]?.style == .floatingIsland && globalOff.perDisplay["studio"] == nil)
}

@Test func pointerModeIsItsOwnItem() {
    #expect(ShowOnPolicy.offersPointerMode(on: laptopAndTwo) && !ShowOnPolicy.offersPointerMode(on: [builtIn]))
    let pointer = policy(.all).togglingPointerMode()
    #expect(pointer.selection == .pointer && pointer.togglingPointerMode().selection == .all)
    // In pointer mode the rows are unchecked; clicking one pins Cranny to that display.
    #expect(pointer.canToggle("built-in", on: laptopAndTwo))
    #expect(pointer.toggling("dell", on: laptopAndTwo).selection == .custom(["dell"]))
    #expect(pointer.toggling("built-in", on: laptopAndTwo).selection == .builtIn)
}

@Test func disconnectedDisplaysStayInACustomList() {
    let custom = policy(.custom(["dell", "projector"]))
    let next = custom.toggling("studio", on: laptopAndTwo)
    #expect(next.selection == .custom(["studio", "dell", "projector"]))           // the projector comes back when reconnected
}

@Test func repeatedDisplayNamesAreNumbered() {
    #expect(ShowOnPolicy.menuTitles(for: ["DELL", "Built-in", "DELL", "DELL"]) == ["DELL", "Built-in", "DELL 2", "DELL 3"])
    #expect(ShowOnPolicy.menuTitles(for: ["A", "B"]) == ["A", "B"])
}

@Test func theDisplayListWritesSettings() {
    let settings = CrannyServices.preview().settings
    let list = DisplayList(settings: settings) { laptopAndTwo }
    list.start()
    defer { list.stop() }
    #expect(list.displays == laptopAndTwo && list.offersPointerMode)
    #expect(list.isShown("built-in") && !list.isShown("studio") && !list.canToggle("built-in"))
    list.toggle("studio")
    #expect(settings[CoreSettings.displaySelection] == .custom(["built-in", "studio"]) && list.canToggle("built-in"))
    list.togglePointerMode()
    #expect(list.followsPointer && !list.isShown("built-in"))
}

// MARK: - Key equivalents

@Test func globalShortcutsShowAsMenuKeyEquivalents() throws {
    let open = try #require(MenuKeyEquivalent.shortcut(for: .openNookDefault))
    #expect(open.key == KeyEquivalent("n") && open.modifiers == [.control, .option])
    let f19 = try #require(MenuKeyEquivalent.shortcut(for: KeyCombo(keyCode: 80, modifiers: [.command, .shift], display: "⇧⌘F19")))
    #expect(f19.key.character == Character(UnicodeScalar(NSF19FunctionKey) ?? " ") && f19.modifiers == [.command, .shift])
    #expect(MenuKeyEquivalent.keyEquivalent(forKeyCode: 49) == .space)
    #expect(MenuKeyEquivalent.keyEquivalent(forKeyCode: 126) == .upArrow)
    #expect(MenuKeyEquivalent.keyEquivalent(forKeyCode: 0x3F) == nil)               // Fn: not a menu key
}

// MARK: - Wiring

@MainActor private func makeServices(login: FakeLoginItem = FakeLoginItem(), repository: String? = "octo/cranny")
    -> (ShellAppServices, ModuleRegistry, OverlayCoordinator) {
    let registry = ModuleRegistry(services: .preview())
    let overlay = OverlayCoordinator(registry: registry, environment: ShellEnvironment())
    ShellContributions.register(in: registry, overlay: overlay)
    let services = ShellAppServices(registry: registry, appControl: ShellAppControl(), overlay: overlay,
                                    settingsWindow: SettingsWindowController(registry: registry),
                                    welcomeWindow: WelcomeWindowController(registry: registry), loginItemService: login,
                                    updateConfiguration: UpdateConfiguration(repository: repository, currentVersion: "0.1.0"),
                                    updateTransport: FakeUpdateTransport([]))
    return (services, registry, overlay)
}

@Test func appServicesBackTheAppControlPort() {
    let login = FakeLoginItem()
    let (services, _, _) = makeServices(login: login)
    services.start()
    defer { services.stop() }
    let control = services.appControl
    #expect(control.loginItem == .disabled && control.update == .idle)
    control.setLaunchAtLogin(true)
    #expect(control.loginItem == .enabled && login.calls == ["register"])
    #expect(control.pause === services.pause && control.demo === services.demo && control.displays === services.displays)
    #expect(control.updates?.isConfigured == true)
}

@Test func theMenuShowsTheEffectiveBindingOnlyWhileRegistered() {
    let (services, registry, overlay) = makeServices()
    services.start()
    overlay.hotKeys.start(registry: registry)
    defer { overlay.hotKeys.stop(); services.stop() }
    let control = services.appControl
    #expect(control.menuShortcut(.togglePin) == nil)                                // off by default
    // ⌃⌥⇧⌘F19: a combination nobody uses, so the test never collides with a real shortcut.
    let combo = KeyCombo(keyCode: 80, modifiers: [.control, .option, .shift, .command], display: "⌃⌥⇧⌘F19")
    #expect(control.setShortcut(.togglePin, combo) == .registered)
    #expect(control.menuShortcut(.togglePin) == MenuKeyEquivalent.shortcut(for: combo))
    control.setShortcut(.togglePin, nil)
    #expect(control.menuShortcut(.togglePin) == nil)
}

#if DEBUG
@Test func menuQAArgumentsParse() {
    let o = QAHooks.Options(arguments: ["Cranny", "--qa-menu", "showOn", "--qa-demo", "on", "--qa-update-check"])
    #expect(o.menu == .showOn && o.demo == true && o.updateCheck && !o.isEmpty)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-demo", "off"]).demo == false)
    #expect(QAHooks.Options(arguments: ["Cranny", "--qa-menu", "sideways", "--qa-demo", "maybe"]).isEmpty)
}
#endif
