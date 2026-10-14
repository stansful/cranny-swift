// CrannyAppShell/Services/ShellAppServices.swift — app-level services (ARCHITECTURE.md §10.0, §10.17).
// Owns launch at login (`LoginItemController`), the update check (`UpdateChecker`), Pause Live Activities
// (`PauseController`), Demo mode (`DemoMode`), the Show On display list and the interactive tutorial, and wires
// them and the windows, the overlay and the hot keys into the `AppControl` port. Nothing here polls: every
// service waits for a notification, an observed settings key or one sleep to a deadline.
import CrannyCore
import CrannyOnboarding
import Foundation

@MainActor final class ShellAppServices {
    let appControl: ShellAppControl
    let loginItems: LoginItemController
    let updates: UpdateChecker
    let pause: PauseController
    let demo: DemoMode
    let displays: DisplayList
    let tutorial: TutorialController
    private let registry: ModuleRegistry
    private let overlay: OverlayCoordinator
    private let settingsWindow: SettingsWindowController
    private let welcomeWindow: WelcomeWindowController

    /// The app's services. Tests inject a fake login item service and update transport (nothing real is touched).
    init(registry: ModuleRegistry, appControl: ShellAppControl, overlay: OverlayCoordinator,
         settingsWindow: SettingsWindowController, welcomeWindow: WelcomeWindowController,
         loginItemService: any LoginItemService = MainAppLoginItem(),
         updateConfiguration: UpdateConfiguration = .main(), updateTransport: any UpdateTransport = URLSessionUpdateTransport()) {
        self.registry = registry; self.appControl = appControl; self.overlay = overlay
        self.settingsWindow = settingsWindow; self.welcomeWindow = welcomeWindow
        let settings = registry.services.settings
        loginItems = LoginItemController(service: loginItemService)
        updates = UpdateChecker(settings: settings, configuration: updateConfiguration, paths: registry.services.paths,
                                transport: updateTransport)
        pause = PauseController(settings: settings)
        demo = DemoMode(settings: settings)
        displays = DisplayList(settings: settings)
        tutorial = TutorialController(registry: registry)
    }

    func start() {
        appControl.connect(settings: registry.services.settings, overlay: overlay, settingsWindow: settingsWindow,
                           welcomeWindow: welcomeWindow, hotKeys: overlay.hotKeys)
        appControl.attach(loginItems: loginItems, updates: updates, pause: pause, demo: demo, displays: displays,
                          tutorial: tutorial, shortcuts: registry.shortcuts)
        loginItems.start()
        pause.start()
        demo.start()
        displays.start()
        updates.start()
    }

    func stop() {
        updates.stop()
        displays.stop()
        demo.stop()
        pause.stop()
        loginItems.stop()
        tutorial.stop()
    }
}
