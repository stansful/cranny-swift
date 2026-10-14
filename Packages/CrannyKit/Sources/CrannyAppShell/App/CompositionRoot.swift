// CrannyAppShell/App/CompositionRoot.swift — the ONLY place that knows every module.
import CrannyCalendar
import CrannyCore
import CrannyHUD
import CrannyMedia
import CrannyMirror
import CrannyNotes
import CrannyQuickApps
import CrannySystemActivities
import CrannyTimer
import CrannyTodos
import CrannyTray
import Foundation

@MainActor enum CompositionRoot {
    /// Registration order = default order of contributions (widget library, settings panes, palette).
    static let modules: [any FeatureModule.Type] = [
        MediaModule.self, CalendarModule.self, QuickAppsModule.self, MirrorModule.self, NotesModule.self,
        TodosModule.self, TimerModule.self, TrayModule.self, HUDModule.self, SystemActivitiesModule.self,
    ]

    /// The services and every module. `defaults` is where the settings live (`ShellDefaults`: the standard domain, or
    /// a Debug QA run's suite).
    static func makeRegistry(notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl,
                             defaults: UserDefaults) -> ModuleRegistry {
        let services = makeServices(notch: notch, environment: environment, app: app, defaults: defaults, paths: .live)
        let registry = ModuleRegistry(services: services)
        for module in modules { registry.register(module) }
        return registry
    }

    /// The service hub: settings in `defaults`, the app's one permissions center (refreshed whenever Cranny becomes
    /// active), haptics gated by the setting, files under `paths`.
    static func makeServices(notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl,
                             defaults: UserDefaults, paths: AppPaths) -> CrannyServices {
        let settings = SettingsStore(defaults: defaults)
        return CrannyServices(settings: settings, permissions: PermissionsCenter(refreshesOnActivation: true),
                              haptics: Haptics(isEnabled: { settings[CoreSettings.haptics] }),
                              paths: paths, notch: notch, environment: environment, app: app)
    }
}
