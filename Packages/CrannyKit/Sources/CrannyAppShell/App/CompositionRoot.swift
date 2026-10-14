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

@MainActor enum CompositionRoot {
    /// Registration order = default order of contributions (widget library, settings panes, palette).
    static let modules: [any FeatureModule.Type] = [
        MediaModule.self, CalendarModule.self, QuickAppsModule.self, MirrorModule.self, NotesModule.self,
        TodosModule.self, TimerModule.self, TrayModule.self, HUDModule.self, SystemActivitiesModule.self,
    ]

    static func makeRegistry(notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl) -> ModuleRegistry {
        let settings = SettingsStore()
        let services = CrannyServices(settings: settings, permissions: PermissionsCenter(),
                                      haptics: Haptics(isEnabled: { settings[CoreSettings.haptics] }),
                                      paths: .live, notch: notch, environment: environment, app: app)
        let registry = ModuleRegistry(services: services)
        for module in modules { registry.register(module) }
        return registry
    }
}
