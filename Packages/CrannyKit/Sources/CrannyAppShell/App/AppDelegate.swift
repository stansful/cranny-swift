// CrannyAppShell/App/AppDelegate.swift — a thin orchestrator (ARCHITECTURE.md §3.4, §10.1).
// Builds the ports and the registry (CompositionRoot), registers the shell's own contributions, then owns and
// starts four components with final initializers: OverlayCoordinator (WP13), SettingsWindowController (WP14),
// WelcomeWindowController (WP15) and ShellAppServices (WP16). `--diagnostics` exits before any window exists.
import AppKit
import CrannyCore
import Foundation

/// Owned by the app target via `@NSApplicationDelegateAdaptor`.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // Ports exist before the registry, because modules receive them in `register(in:)`.
    let environment = ShellEnvironment()
    let notchControl = ShellNotchControl()
    let appControl = ShellAppControl()

    private(set) var registry: ModuleRegistry?
    private(set) var overlay: OverlayCoordinator?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var appServices: ShellAppServices?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = CompositionRoot.makeRegistry(notch: notchControl, environment: environment, app: appControl)
        self.registry = registry
        if let out = Diagnostics.argument("--diagnostics") {
            Task { await Diagnostics.write(to: out, registry: registry); NSApp.terminate(nil) }
            return
        }
        environment.start(settings: registry.services.settings)

        let overlay = OverlayCoordinator(registry: registry, environment: environment)
        ShellContributions.register(in: registry, overlay: overlay)
        let settingsWindow = SettingsWindowController(registry: registry)
        let welcomeWindow = WelcomeWindowController(registry: registry)
        let appServices = ShellAppServices(registry: registry, appControl: appControl, overlay: overlay,
                                           settingsWindow: settingsWindow, welcomeWindow: welcomeWindow)
        self.overlay = overlay
        self.settingsWindow = settingsWindow
        self.welcomeWindow = welcomeWindow
        self.appServices = appServices

        appServices.start()
        overlay.start()
        #if DEBUG
        QAHooks.apply(QAHooks.Options(arguments: CommandLine.arguments), to: overlay, appControl: appControl)
        #endif
        Task { await registry.runLaunchHooks() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        registry?.runTerminateHooks()
    }

    /// Launching Cranny again (Finder, Spotlight) opens Settings, so a hidden menu bar icon never locks anyone out.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appControl.openSettings(nil)
        return false
    }
}
