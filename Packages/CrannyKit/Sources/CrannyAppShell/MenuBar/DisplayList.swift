// CrannyAppShell/MenuBar/DisplayList.swift — the connected displays behind the menu bar's Show On ▸ submenu.
// Refreshed on `didChangeScreenParametersNotification` only (no polling); clicks go through `ShowOnPolicy`
// and are written to `CoreSettings`, which the overlay observes to rebuild its panels.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation

@MainActor @Observable final class DisplayList {
    private(set) var displays: [ConnectedDisplay] = []
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let source: @MainActor () -> [ConnectedDisplay]
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// `source` lists the connected displays (tests and previews pass fixed ones); default: `NSScreen.screens`.
    init(settings: SettingsStore, source: @escaping @MainActor () -> [ConnectedDisplay] = DisplayList.connectedScreens) {
        self.settings = settings; self.source = source
    }

    func start() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }                     // queue: .main
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// The policy as stored now (read inside menu bodies, so the checkmarks follow every writer).
    var policy: ShowOnPolicy {
        ShowOnPolicy(selection: settings[CoreSettings.displaySelection], perDisplay: settings[CoreSettings.perDisplay],
                     noNotchStyle: settings[CoreSettings.noNotchStyle])
    }

    func isShown(_ key: DisplayKey) -> Bool {
        let policy = policy
        return policy.selection != .pointer && policy.shownKeys(on: displays).contains(key)
    }
    func canToggle(_ key: DisplayKey) -> Bool { policy.canToggle(key, on: displays) }
    var followsPointer: Bool { settings[CoreSettings.displaySelection] == .pointer }
    var offersPointerMode: Bool { ShowOnPolicy.offersPointerMode(on: displays) }

    func toggle(_ key: DisplayKey) { write(policy.toggling(key, on: displays)) }
    func togglePointerMode() { write(policy.togglingPointerMode()) }

    // MARK: Private

    private func write(_ next: ShowOnPolicy) {
        settings[CoreSettings.displaySelection] = next.selection
        settings[CoreSettings.perDisplay] = next.perDisplay
    }

    private func refresh() {
        let next = source()
        if next != displays { displays = next }
    }

    /// `NSScreen.screens` as menu rows (primary first), with unique titles.
    static func connectedScreens() -> [ConnectedDisplay] {
        let screens = NSScreen.screens
        let titles = ShowOnPolicy.menuTitles(for: screens.map(\.localizedName))
        return zip(screens, titles).compactMap { screen, title in
            guard let key = ThemeResolver.displayKey(screen) else { return nil }
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return ConnectedDisplay(key: key, name: title, isBuiltIn: number.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                                    hasNotch: screen.safeAreaInsets.top > 0)
        }
    }
}
