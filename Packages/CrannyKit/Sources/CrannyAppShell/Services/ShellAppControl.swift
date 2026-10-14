// CrannyAppShell/Services/ShellAppControl.swift — the `AppControl` port (ARCHITECTURE.md §3.9), WP16.
// Created before the registry (modules receive it in `register(in:)`); `ShellAppServices.start()` wires it to the
// windows, the overlay and the hot keys (`connect`), then to the app services (`attach`): launch at login,
// the update check, Pause Live Activities, Demo mode, the Show On displays and the tutorial. The menu bar extra
// reads everything through this one object.
import AppKit
import CrannyCore
import CrannyOnboarding
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class ShellAppControl: AppControl {
    /// Tracked, so views that read settings through it refresh once it is wired.
    private(set) var settings: SettingsStore?
    @ObservationIgnored private weak var overlay: OverlayCoordinator?
    @ObservationIgnored private weak var settingsWindow: SettingsWindowController?
    @ObservationIgnored private weak var welcomeWindow: WelcomeWindowController?
    /// Observable itself: `shortcutState(_:)` reads its `states`, so views refresh when a registration changes.
    private var hotKeys: HotKeyCenter?

    // App services (owned by `ShellAppServices`; nil until `attach`, e.g. in previews of an unwired menu).
    private(set) var loginItems: LoginItemController?
    private(set) var updates: UpdateChecker?
    private(set) var pause: PauseController?
    private(set) var demo: DemoMode?
    private(set) var displays: DisplayList?
    @ObservationIgnored private var tutorial: TutorialController?
    /// Default combinations of the registered global shortcuts (the menu shows the effective binding).
    @ObservationIgnored private var defaultCombos: [ShortcutID: KeyCombo] = [:]
    /// Whether a panel is open, read from the panels themselves (not inferred from events, which a panel removed
    /// with its display would never send).
    var isPanelOpen: Bool { overlay?.isOpen ?? false }

    init() {}

    func connect(settings: SettingsStore, overlay: OverlayCoordinator, settingsWindow: SettingsWindowController,
                 welcomeWindow: WelcomeWindowController, hotKeys: HotKeyCenter) {
        self.settings = settings; self.overlay = overlay; self.settingsWindow = settingsWindow
        self.welcomeWindow = welcomeWindow; self.hotKeys = hotKeys
    }

    func attach(loginItems: LoginItemController, updates: UpdateChecker, pause: PauseController, demo: DemoMode,
                displays: DisplayList, tutorial: TutorialController, shortcuts: [GlobalShortcut]) {
        self.loginItems = loginItems; self.updates = updates; self.pause = pause; self.demo = demo
        self.displays = displays; self.tutorial = tutorial
        defaultCombos = Dictionary(shortcuts.compactMap { s in s.defaultCombo.map { (s.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: AppControl

    /// Read fresh whenever Cranny becomes active (Settings, Welcome), never cached as a Bool (§7.9).
    var loginItem: LoginItemState { loginItems?.state ?? .disabled }
    /// Turning it on while it `.requiresApproval`, or again after macOS refused it (`.unavailable`), opens
    /// System Settings ▸ General ▸ Login Items: that is what Settings' "Open Login Items…" calls.
    func setLaunchAtLogin(_ enabled: Bool) { loginItems?.setEnabled(enabled) }

    var update: UpdateState { updates?.state ?? .idle }
    /// Settings ▸ About's "Check for Updates": the result shows inline through `update` (no alert).
    func checkForUpdates() { updates?.checkNow() }

    func shortcutState(_ id: ShortcutID) -> ShortcutState { hotKeys?.state(id) ?? .off }
    /// Writes the binding, re-registers at once and returns the resulting state (§3.9). `HotKeyCenter` also
    /// observes `CoreSettings.shortcuts` for every other writer (Reset All, Undo) and skips this change.
    @discardableResult func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState {
        settings?[CoreSettings.shortcuts][id] = .some(combo)
        hotKeys?.reapply()
        return shortcutState(id)
    }
    func openSettings(_ page: SettingsPageID?) { settingsWindow?.show(page: page) }
    func showWelcome() { welcomeWindow?.show() }
    func startTutorial() { tutorial?.start() }
    func showOnNotch(_ state: PreviewStageState) { overlay?.play(state, for: .seconds(5)) }
    func resetAllSettings() { settings?.resetAll() }
    func quit() { NSApp.terminate(nil) }
    /// Settings ▸ Keyboard records a shortcut: the global hot keys pause, so pressing a bound one records it.
    func setShortcutRecording(_ recording: Bool) { hotKeys?.setPaused(recording) }

    // MARK: Menu bar helpers (not part of the port)

    var showsMenuBarIcon: Bool {
        get { settings?[CoreSettings.showsMenuBarIcon] ?? true }
        set { settings?[CoreSettings.showsMenuBarIcon] = newValue }
    }
    var isPinned: Bool { overlay?.isPinned ?? false }
    func setPinned(_ pinned: Bool) { overlay?.setPinned(pinned) }

    /// How "Open Cranny" in the menu opens the panel: like ⌃⌥N while nothing is open (the pointer's display,
    /// keyboard focus), otherwise by opening on the pointer's display again — never by closing, unlike the
    /// hot key, which toggles. (If the open panel's display went away, that opens a new one where the user is.)
    enum OpenRequest: Equatable {
        case hotKey, reopen
        init(isPanelOpen: Bool) { self = isPanelOpen ? .reopen : .hotKey }
    }
    var openRequest: OpenRequest { OpenRequest(isPanelOpen: isPanelOpen) }

    /// "Open Cranny" (menu bar): opens, never closes.
    func openPanel() {
        guard let overlay else { return }
        switch openRequest {
        case .hotKey: overlay.toggleOpen()                     // nothing is open: the hot key's open
        case .reopen: overlay.notchControl.open(page: nil, focus: nil, reason: .keyboard)
        }
    }

    /// "About Cranny" opens Settings ▸ About: the icon, version, updates, licence and acknowledgements (§11.1).
    func showAbout() { openSettings(.about) }

    /// "Check for Updates…": checks and opens Settings ▸ About, which shows "Checking…" and then the result inline
    /// (`update`); the menu item follows the same state. Settings opens in response to the click (cooperative
    /// activation, DESIGN.md §11.1). Nothing appears later by itself, so a slow answer never takes focus from
    /// another app, and no modal alert ever blocks the panel or Settings.
    func checkForUpdatesFromMenu() {
        checkForUpdates()
        openSettings(.about)
    }

    /// The release page of an available update, in the default browser.
    func openReleasePage() {
        guard case .available(_, let url) = update else { return }
        NSWorkspace.shared.open(url)
    }

    /// The key equivalent a menu item shows for a global shortcut: its effective binding, only while registered.
    func menuShortcut(_ id: ShortcutID) -> KeyboardShortcut? {
        guard shortcutState(id) == .registered, let settings else { return nil }
        // Same rule as `HotKeyCenter.effectiveCombo`: a binding (even an explicit nil = off) wins over the default.
        let combo: KeyCombo? = if let binding = settings[CoreSettings.shortcuts][id] { binding } else { defaultCombos[id] }
        return combo.flatMap(MenuKeyEquivalent.shortcut(for:))
    }
}
