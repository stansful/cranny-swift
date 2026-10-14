// CrannyAppShell/Services/DemoMode.swift — Demo mode (DESIGN.md §11.1 General, §13, §14.3).
// The only writer of `CoreSettings.demoMode`. Everything else follows the key: `ShellEnvironment`
// publishes `isDemoMode` (the panel never auto-closes or hides and shows on full screen, sounds are muted,
// calendar titles are redacted when `demoRedactsCalendar` is on), and the menu bar icon wears its 4-pt dot.
import CrannyCore
import Foundation
import Observation
import os

private let log = Log.logger(.app)

@MainActor @Observable final class DemoMode {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var token: ObservationToken?

    init(settings: SettingsStore) { self.settings = settings }

    /// Observable through the settings key (menus and views refresh when it changes).
    var isOn: Bool { settings[CoreSettings.demoMode] }

    func set(_ on: Bool) {
        guard settings[CoreSettings.demoMode] != on else { return }
        settings[CoreSettings.demoMode] = on
        log.info("demo mode \(on ? "on" : "off", privacy: .public)")
    }

    func toggle() { set(!isOn) }

    /// The app's instance: mirrors the key into the menu bar icon's badge (also after Reset All and Undo).
    /// Tests pass their own `badge` sink instead of the icon's shared state.
    func start(badge: @escaping @MainActor (Bool) -> Void = { MenuBarIcon.showsDemoBadge = $0 }) {
        badge(isOn)
        token = observe({ [settings] in settings[CoreSettings.demoMode] }) { badge($0) }
    }

    func stop() { token = nil }
}
