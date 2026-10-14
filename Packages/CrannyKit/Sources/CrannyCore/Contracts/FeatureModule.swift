// CrannyCore/Contracts/FeatureModule.swift
// How a module plugs into the app: one static entry point, contributions recorded in a registry.
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
    public let services: CrannyServices

    public private(set) var widgets: [AnyNookWidget] = []
    public private(set) var pages: [PageDescriptor] = []
    public private(set) var activities: [RegisteredActivity] = []
    public private(set) var settingsPages: [SettingsPage] = []
    public private(set) var commandProviders: [any PaletteCommandProvider] = []
    public private(set) var shortcuts: [GlobalShortcut] = []
    public private(set) var captureTargets: [CaptureTarget] = []
    public private(set) var permissionUses: [PermissionUse] = []

    private var launchHooks: [@MainActor () async -> Void] = []
    private var terminateHooks: [@MainActor () -> Void] = []
    /// The module currently registering (set by `register(_:)`); used to attribute diagnostics.
    public private(set) var registeringModule: ModuleID?

    public init(services: CrannyServices) { self.services = services }

    /// Called by the composition root for each module, in order.
    public func register(_ module: any FeatureModule.Type) {
        registeringModule = module.id
        module.register(in: self)
        registeringModule = nil
    }

    // MARK: Contributions
    public func add<W: NookWidget>(widget: W) {
        precondition(self.widget(widget.id) == nil, "duplicate widget id \(widget.id)")
        widgets.append(AnyNookWidget(widget))
    }
    public func add(page: PageDescriptor) { pages.append(page) }
    public func add<A: LiveActivity>(activity: A, kind: ActivityKind,
                                     sample: (@MainActor () -> any LiveActivity)? = nil,
                                     options: (@MainActor () -> AnyView)? = nil) {
        precondition(activity.id == kind.id, "activity id must equal kind id")
        activities.append(RegisteredActivity(kind: kind, activity: activity, makeSample: sample, makeOptions: options))
    }
    /// Empty `namespaces` = the registering module (used by "Reset ‹Pane›…").
    public func add(settingsPage: SettingsPage) {
        var page = settingsPage
        if page.namespaces.isEmpty, let module = registeringModule { page.namespaces = [module] }
        settingsPages.append(page)
    }
    public func add(commands provider: any PaletteCommandProvider) { commandProviders.append(provider) }
    public func add(shortcut: GlobalShortcut) { shortcuts.append(shortcut) }
    public func add(captureTarget: CaptureTarget) { captureTargets.append(captureTarget) }
    /// `optIn`: the module's off-by-default switch that the permission serves (`PermissionUse.optIn`).
    public func declare(_ kind: PermissionKind, reason: String, optIn: SettingKey<Bool>? = nil) {
        permissionUses.append(PermissionUse(kind: kind, module: registeringModule ?? .shell, reason: reason,
                                            optIn: optIn))
    }

    /// Runs after ALL modules registered and the services are wired (start observers, load files here).
    public func onLaunch(_ action: @escaping @MainActor () async -> Void) { launchHooks.append(action) }
    /// Runs from `applicationWillTerminate` (flush files, stop helpers). Must be fast and synchronous.
    public func onTerminate(_ action: @escaping @MainActor () -> Void) { terminateHooks.append(action) }

    // MARK: Shell side
    public func widget(_ id: WidgetID) -> AnyNookWidget? { widgets.first { $0.id == id } }
    public func activity(_ id: ActivityID) -> RegisteredActivity? { activities.first { $0.id == id } }
    public func runLaunchHooks() async { for hook in launchHooks { await hook() } }
    public func runTerminateHooks() { for hook in terminateHooks { hook() } }
}
