// CrannyCore/Contracts/FeatureModule.swift
// How a module plugs into the app: one static entry point, contributions recorded in a registry.
import os
import SwiftUI

/// Every layer-1 module exposes exactly one public type conforming to this (e.g. `TimerModule`).
/// The shell's composition root lists them; nothing else references module internals.
@MainActor public protocol FeatureModule {
    /// Namespace of the module's settings keys, storage directory and contributions.
    static var id: ModuleID { get }
    /// Called once at launch, before any window exists. Create the module's models, then contribute.
    /// Keep it cheap: no I/O, no permission prompts, no hardware. Start work in `registry.onLaunch`.
    static func register(in registry: ModuleRegistry)
}

/// Collects contributions. Owned by the shell; filled once at launch; read-only afterwards.
@MainActor public final class ModuleRegistry {
    /// The service hub every module receives: settings, permissions, paths and the ports to the shell and to other
    /// modules (`services.notch`, `services.nowPlaying`, …).
    public let services: CrannyServices

    /// Nook widgets, in registration order (the widget library's default order).
    public private(set) var widgets: [AnyNookWidget] = []
    /// Module pages in the Nook header (the Tray page). The grid page and user pages belong to the shell.
    public private(set) var pages: [PageDescriptor] = []
    /// Live activities with their kinds, samples and Settings ▸ Live Activities options.
    public private(set) var activities: [RegisteredActivity] = []
    /// Settings panes contributed by modules and by the shell.
    public private(set) var settingsPages: [SettingsPage] = []
    /// ⌘K command providers, queried on every keystroke.
    public private(set) var commandProviders: [any PaletteCommandProvider] = []
    /// System-wide shortcuts; the shell registers them and stores the user's bindings.
    public private(set) var shortcuts: [GlobalShortcut] = []
    /// Type-to-capture targets (Notes, To-dos).
    public private(set) var captureTargets: [CaptureTarget] = []
    /// Permissions the modules may ask for, with their reasons (Settings ▸ Permissions, onboarding).
    public private(set) var permissionUses: [PermissionUse] = []

    /// A hook and the module that registered it (`.shell` outside `register(_:)`).
    private struct Hook<Action> {
        let module: ModuleID
        let action: Action
    }
    private var launchHooks: [Hook<@MainActor () async -> Void>] = []
    private var terminateHooks: [Hook<@MainActor () -> Void>] = []
    /// The module currently registering (set by `register(_:)`); used to attribute diagnostics.
    public private(set) var registeringModule: ModuleID?
    /// Modules whose launch hooks have all finished during `runLaunchHooks()`, in no particular order. A module
    /// still loading (a slow volume, a large index) is missing; the shell can tell from here what has started.
    public private(set) var launchedModules: Set<ModuleID> = []

    /// An empty registry over `services`. The shell makes one per process; tests and previews make their own.
    public init(services: CrannyServices) { self.services = services }

    /// Called by the composition root for each module, in order.
    public func register(_ module: any FeatureModule.Type) {
        registeringModule = module.id
        module.register(in: self)
        registeringModule = nil
    }

    // MARK: Contributions

    /// Adds a Nook widget. Widget ids are unique (a duplicate is a programmer error); a real widget replaces the
    /// preview stand-in of its id (`addPreviewStandIns()`).
    public func add<W: NookWidget>(widget: W) {
        if let index = widgets.firstIndex(where: { $0.id == widget.id }), widgets[index].base is PreviewStandInWidget {
            widgets[index] = AnyNookWidget(widget)
            return
        }
        precondition(self.widget(widget.id) == nil, "duplicate widget id \(widget.id)")
        widgets.append(AnyNookWidget(widget))
    }
    /// Adds a full-width page to the Nook header.
    public func add(page: PageDescriptor) { pages.append(page) }
    /// Adds a live activity. `sample` builds a self-contained instance with sample data (Settings "Simulate",
    /// onboarding); `options` adds rows under the kind in Settings ▸ Live Activities.
    public func add<A: LiveActivity>(activity: A, kind: ActivityKind,
                                     sample: (@MainActor () -> any LiveActivity)? = nil,
                                     options: (@MainActor () -> AnyView)? = nil) {
        precondition(activity.id == kind.id, "activity id must equal kind id")
        activities.append(RegisteredActivity(kind: kind, activity: activity, makeSample: sample, makeOptions: options))
    }
    /// Adds a Settings pane. Empty `namespaces` = the registering module (used by "Reset ‹Pane›…").
    public func add(settingsPage: SettingsPage) {
        var page = settingsPage
        if page.namespaces.isEmpty, let module = registeringModule { page.namespaces = [module] }
        settingsPages.append(page)
    }
    /// Adds a ⌘K command provider.
    public func add(commands provider: any PaletteCommandProvider) { commandProviders.append(provider) }
    /// Adds a system-wide shortcut.
    public func add(shortcut: GlobalShortcut) { shortcuts.append(shortcut) }
    /// Adds a type-to-capture target.
    public func add(captureTarget: CaptureTarget) { captureTargets.append(captureTarget) }
    /// Declares a permission the registering module may request, with its localized one-line reason.
    public func declare(_ kind: PermissionKind, reason: String) {
        permissionUses.append(PermissionUse(kind: kind, module: registeringModule ?? .shell, reason: reason))
    }

    /// Runs after ALL modules registered and the services are wired (start observers, load files here). Hooks of
    /// different modules run concurrently on the main actor (see `runLaunchHooks()`): never rely on another
    /// module's hook having run, and leave the main actor for I/O.
    public func onLaunch(_ action: @escaping @MainActor () async -> Void) {
        launchHooks.append(Hook(module: registeringModule ?? .shell, action: action))
    }
    /// Runs from `applicationWillTerminate` (flush files, stop helpers). Must be fast and synchronous. It may run
    /// before this module's launch hook finished (a quit during a slow load): check `launchedModules` or keep
    /// the module's own "loaded" state before writing anything.
    public func onTerminate(_ action: @escaping @MainActor () -> Void) {
        terminateHooks.append(Hook(module: registeringModule ?? .shell, action: action))
    }

    // MARK: Shell side

    /// The registered widget with `id`, if any.
    public func widget(_ id: WidgetID) -> AnyNookWidget? { widgets.first { $0.id == id } }
    /// The registered activity with `id`, if any.
    public func activity(_ id: ActivityID) -> RegisteredActivity? { activities.first { $0.id == id } }

    /// Starts every launch hook at once, in registration order, and returns when all have finished. The hooks are
    /// main-actor closures, so they interleave only at their `await`s: a module that reads files or resolves
    /// bookmarks (Notes, To-dos, Timer, Tray) never delays another module's synchronous start (the HUD's event tap,
    /// the battery observers). Each module enters `launchedModules` when its last hook finishes; durations are logged.
    public func runLaunchHooks() async {
        unfinishedLaunchHooks = Dictionary(launchHooks.map { ($0.module, 1) }, uniquingKeysWith: +)
        let tasks = launchHooks.map { hook in
            Task {
                let started = ContinuousClock.now
                await hook.action()
                launchHookFinished(hook.module, after: ContinuousClock.now - started)
            }
        }
        for task in tasks { await task.value }
    }

    private var unfinishedLaunchHooks: [ModuleID: Int] = [:]

    private func launchHookFinished(_ module: ModuleID, after duration: Duration) {
        let milliseconds = duration.timeInterval * 1000
        Log.logger(.app).info("launch hook of \(module.rawValue, privacy: .public) took \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        unfinishedLaunchHooks[module, default: 1] -= 1
        if unfinishedLaunchHooks[module] == 0 { launchedModules.insert(module) }
    }

    /// Runs every terminate hook, in registration order (from `applicationWillTerminate`).
    public func runTerminateHooks() { for hook in terminateHooks { hook.action() } }
}
