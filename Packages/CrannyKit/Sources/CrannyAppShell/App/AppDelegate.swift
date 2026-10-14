// CrannyAppShell/App/AppDelegate.swift — a thin orchestrator (ARCHITECTURE.md §3.4, §10.1).
// Builds the ports and the registry (CompositionRoot), registers the shell's own contributions, then owns and
// starts four components with final initializers: OverlayCoordinator, SettingsWindowController,
// WelcomeWindowController and ShellAppServices. `--diagnostics` exits before any window exists, and
// before any module launched, so no terminate hook runs then either (`LaunchGate`), and before the one-time settings
// upgrade, so it writes no preference. `ShellDefaults` picks where settings live (a Debug QA run's own suite).
// Energy: a few seconds after launch, while the app is idle, the Metal effects are prepared off the main thread
// (`EffectsPreparation`), so the first open of the panel compiles nothing during its animation.
import AppKit
import CrannyCore
import CrannyEffects
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
    /// Terminate hooks only after launch hooks; a quit during the launch waits for them.
    private let launchGate = LaunchGate()

    /// Created by `@NSApplicationDelegateAdaptor`; everything starts in `applicationDidFinishLaunching`.
    public override init() { super.init() }

    /// Builds the registry, then starts the overlay, windows and app services (or writes `--diagnostics` and quits).
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = ShellDefaults.forLaunch()           // the user's preferences, or a Debug QA run's own suite
        let registry = CompositionRoot.makeRegistry(notch: notchControl, environment: environment, app: appControl,
                                                    defaults: defaults.defaults)
        self.registry = registry
        if let out = Diagnostics.argument("--diagnostics") {
            Task { await Diagnostics.write(to: out, registry: registry); NSApp.terminate(nil) }
            return
        }
        registry.services.settings.upgradeStoredSettings()   // once per install and revision; never in --diagnostics
        environment.start(settings: registry.services.settings)

        let overlay = OverlayCoordinator(registry: registry, environment: environment)
        ShellContributions.register(in: registry, overlay: overlay)
        let settingsWindow = SettingsWindowController(registry: registry, defaults: defaults)
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
        // Drop folders of file promises a crash (or a quit mid-drop) left behind.
        let paths = registry.services.paths
        Task { await FilePromiseResolver.sweepIncoming(paths: paths) }
        launchGate.launch { await registry.runLaunchHooks() }
        prepareEffects(settings: registry.services.settings)
    }

    /// The light's Metal pipelines and the moments' shaders, compiled at utility priority once the launch has settled.
    /// Skipped while Appearance ▸ Ambience is Off: then the first open that shows light builds them itself, as before.
    private func prepareEffects(settings: SettingsStore) {
        guard settings[CoreSettings.ambience] != .off else { return }
        Task(priority: .utility) {
            try? await Task.sleep(for: Self.effectsPreparationDelay, tolerance: .seconds(1))
            await EffectsPreparation.prepare()
        }
    }

    /// After the modules' launch hooks and the first display facts, so it competes with nothing the user sees.
    private static let effectsPreparationDelay: Duration = .seconds(5)

    /// A quit while the modules are still launching waits for them (at most `LaunchGate.quitWait`), so no terminate
    /// hook saves or deletes state that its launch hook has not restored yet.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        launchGate.defersQuit { NSApp.reply(toApplicationShouldTerminate: true) } ? .terminateLater : .terminateNow
    }

    /// Runs the modules' terminate hooks (stop helpers, flush stores) — only if they launched (never in
    /// `--diagnostics`, whose quit must not touch the user's data) — and deletes the drop folders still there.
    public func applicationWillTerminate(_ notification: Notification) {
        guard launchGate.runsTerminateHooks, let registry else { return }
        registry.runTerminateHooks()
        FilePromiseResolver.sweepIncomingNow(paths: registry.services.paths)
    }

    /// Launching Cranny again (Finder, Spotlight) opens Settings, so a hidden menu bar icon never locks anyone out.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appControl.openSettings(nil)
        return false
    }
}
