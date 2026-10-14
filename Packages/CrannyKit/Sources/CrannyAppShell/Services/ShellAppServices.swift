// CrannyAppShell/Services/ShellAppServices.swift — app-level services (ARCHITECTURE.md §10.0, WP16).
// Owns `ShellAppControl` and will own `LoginItemController`, `UpdateChecker`, `PauseController` and `DemoMode`.
// WP0: wires the AppControl port to the windows, the overlay and the hot keys; nothing touches the network.
import CrannyCore
import Foundation

@MainActor final class ShellAppServices {
    let appControl: ShellAppControl
    private let registry: ModuleRegistry
    private let overlay: OverlayCoordinator
    private let settingsWindow: SettingsWindowController
    private let welcomeWindow: WelcomeWindowController

    init(registry: ModuleRegistry, appControl: ShellAppControl, overlay: OverlayCoordinator,
         settingsWindow: SettingsWindowController, welcomeWindow: WelcomeWindowController) {
        self.registry = registry; self.appControl = appControl; self.overlay = overlay
        self.settingsWindow = settingsWindow; self.welcomeWindow = welcomeWindow
    }

    func start() {
        appControl.connect(settings: registry.services.settings, overlay: overlay, settingsWindow: settingsWindow,
                           welcomeWindow: welcomeWindow, hotKeys: overlay.hotKeys)
        // WP16: LoginItemController.refresh(), UpdateChecker.scheduleDaily(), PauseController, DemoMode.
    }
}
