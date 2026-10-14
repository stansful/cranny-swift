// CrannyAppShell/Services/ShellAppControl.swift — the `AppControl` port (ARCHITECTURE.md §3.9), WP16.
// Created before the registry; `ShellAppServices.start()` wires it to the windows, the overlay and the hot keys.
// WP0 implements open Settings / Welcome, Show on Notch, shortcut bindings, Reset All and quit; WP16 adds the
// login item (SMAppService) and the update check.
import AppKit
import CrannyCore
import Foundation
import Observation

@MainActor @Observable final class ShellAppControl: AppControl {
    var loginItem: LoginItemState = .disabled
    var update: UpdateState = .idle

    /// Tracked, so views that read settings through it refresh once it is wired.
    private(set) var settings: SettingsStore?
    @ObservationIgnored private weak var overlay: OverlayCoordinator?
    @ObservationIgnored private weak var settingsWindow: SettingsWindowController?
    @ObservationIgnored private weak var welcomeWindow: WelcomeWindowController?
    @ObservationIgnored private var hotKeys: HotKeyCenter?

    init() {}

    func connect(settings: SettingsStore, overlay: OverlayCoordinator, settingsWindow: SettingsWindowController,
                 welcomeWindow: WelcomeWindowController, hotKeys: HotKeyCenter) {
        self.settings = settings; self.overlay = overlay; self.settingsWindow = settingsWindow
        self.welcomeWindow = welcomeWindow; self.hotKeys = hotKeys
    }

    // MARK: AppControl

    func setLaunchAtLogin(_ enabled: Bool) {}              // WP16: LoginItemController (SMAppService.mainApp, §7.9)
    func checkForUpdates() {}                               // WP16: UpdateChecker (GitHub Releases, §7.11)
    func shortcutState(_ id: ShortcutID) -> ShortcutState { hotKeys?.state(id) ?? .off }
    /// Writes the binding only: `HotKeyCenter` observes `CoreSettings.shortcuts` and re-registers (§10.0).
    @discardableResult func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState {
        settings?[CoreSettings.shortcuts][id] = .some(combo)
        return shortcutState(id)
    }
    func openSettings(_ page: SettingsPageID?) { settingsWindow?.show(page: page) }
    func showWelcome() { welcomeWindow?.show() }
    func startTutorial() {}                                 // WP15/WP16: TutorialController.start()
    func showOnNotch(_ state: PreviewStageState) { overlay?.play(state, for: .seconds(5)) }
    func resetAllSettings() { settings?.resetAll() }
    func quit() { NSApp.terminate(nil) }

    // MARK: Menu bar helpers (not part of the port)

    var showsMenuBarIcon: Bool {
        get { settings?[CoreSettings.showsMenuBarIcon] ?? true }
        set { settings?[CoreSettings.showsMenuBarIcon] = newValue }
    }
    var isPinned: Bool { overlay?.isPinned ?? false }
    func toggleOpen() { overlay?.toggleOpen() }
    func setPinned(_ pinned: Bool) { overlay?.setPinned(pinned) }
    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
