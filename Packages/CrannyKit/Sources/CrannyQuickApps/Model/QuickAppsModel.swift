// CrannyQuickApps/Model/QuickAppsModel.swift — the module's state: the tiles, launching and running them.
// Editing (add, remove, reorder, appearance) is in QuickAppsModel+Editing.swift.
//
// Energy: `init` does nothing. `start()` (registry.onLaunch) resolves the quick apps once and subscribes to app
// launch/quit notifications; the Shortcuts list is read only on demand (ShortcutsCatalog). Nothing polls.
import Accessibility
import CrannyCore
import Foundation
import Observation
import os

nonisolated private let log = Log.logger(.quickApps)

@MainActor @Observable final class QuickAppsModel {
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let notch: any NotchControl
    @ObservationIgnored let appControl: any AppControl
    @ObservationIgnored let environment: any SystemEnvironment
    @ObservationIgnored let haptics: Haptics
    @ObservationIgnored let launcher: any AppLaunching
    let catalog: AppCatalog
    let running: RunningAppsObserver
    let shortcutsCatalog: ShortcutsCatalog
    let runs: ShortcutRuns

    /// The launcher's own edit mode: remove badges, the "+" tile, drag to reorder. Ends when the panel closes.
    var isEditing = false
    /// Whether a panel is open (from `NotchEvent`s): a shortcut that finishes while it is closed flashes its result.
    private(set) var isPanelOpen = false

    @ObservationIgnored private var observations: [ObservationToken] = []
    @ObservationIgnored private var notchObserver: UUID?
    @ObservationIgnored private var started = false

    init(services: CrannyServices, resolver: any AppResolving = WorkspaceAppResolver(),
         launcher: any AppLaunching = WorkspaceLauncher(), cli: ShortcutsCLI = ShortcutsCLI(),
         running: RunningAppsObserver = RunningAppsObserver()) {
        settings = services.settings
        notch = services.notch
        appControl = services.app
        environment = services.environment
        haptics = services.haptics
        self.launcher = launcher
        catalog = AppCatalog(resolver: resolver)
        self.running = running
        shortcutsCatalog = ShortcutsCatalog(cli: cli)
        runs = ShortcutRuns(cli: cli)
    }

    // MARK: - Lifecycle (registry.onLaunch / onTerminate)

    func start() async {
        guard !started else { return }
        started = true
        running.onLaunch = { [weak self] bundleID in self?.appDidLaunch(bundleID) }
        running.start()
        observations = [
            observe({ [settings] in settings[QuickAppsSettings.apps] }) { [weak self] apps in
                guard let self else { return }
                Task { await self.catalog.refresh(apps.map(\.bundleID)) }
            },
            observe({ [shortcutsCatalog] in shortcutsCatalog.shortcuts }) { [weak self] list in self?.syncNames(with: list) },
        ]
        notchObserver = notch.addEventObserver { [weak self] event in self?.handle(event) }
        await catalog.refresh(appEntries.map(\.bundleID))
    }

    func stop() {
        runs.cancelAll()
        running.stop()
        observations = []
        if let notchObserver { notch.removeEventObserver(notchObserver) }
        notchObserver = nil
    }

    private func handle(_ event: NotchEvent) {
        switch event {
        case .opened:
            isPanelOpen = true
        case .closed:
            isPanelOpen = false
            isEditing = false
        case .paletteOpened:
            Task { await shortcutsCatalog.refresh(maximumAge: 300) }
        default:
            break
        }
    }

    /// A quick app that was not installed just launched: it was installed meanwhile.
    private func appDidLaunch(_ bundleID: String) {
        guard catalog.isMissing(bundleID) else { return }
        Task { await catalog.refresh(appEntries.map(\.bundleID)) }
    }

    // MARK: - Tiles

    var appEntries: [AppEntry] { settings[QuickAppsSettings.apps] }
    var shortcutEntries: [ShortcutEntry] { settings[QuickAppsSettings.shortcuts] }
    var showsLabels: Bool { settings[QuickAppsSettings.showsLabels] }

    /// Every tile id in launcher order, including apps that are not installed.
    var arrangement: [TileID] {
        LauncherOrder.arrange(apps: appEntries, shortcuts: shortcutEntries, order: settings[QuickAppsSettings.order])
    }

    /// The tiles the launcher shows, in order (apps that are not installed are hidden).
    var tiles: [LauncherTile] {
        let shortcuts = Dictionary(shortcutEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return arrangement.compactMap { id in
            switch id {
            case .app(let bundleID): catalog.app(bundleID).map(LauncherTile.app)
            case .shortcut(let shortcutID): shortcuts[shortcutID].map(LauncherTile.shortcut)
            }
        }
    }

    /// Whether the launcher can say "empty" yet (the first app lookup finished).
    var isReady: Bool { catalog.hasResolved || appEntries.isEmpty }

    func isVisible(_ id: TileID) -> Bool {
        switch id {
        case .app(let bundleID): catalog.app(bundleID) != nil
        case .shortcut: true
        }
    }

    // MARK: - Activation

    /// Click, ↩, ⌥1–⌥9 or ⌘K: opens the app, or runs the shortcut (stops it when it is running).
    func activate(_ tile: LauncherTile) {
        switch tile {
        case .app(let app): open(app)
        case .shortcut(let entry): toggleRun(entry)
        }
    }

    func open(_ app: ResolvedApp) {
        Task {
            do {
                try await launcher.open(app.url)
                notch.close()                     // the app comes forward; the panel gets out of its way
            } catch {
                log.error("could not open \(app.bundleID, privacy: .public)")
                await catalog.refresh(appEntries.map(\.bundleID))
            }
        }
    }

    func toggleRun(_ entry: ShortcutEntry) {
        if runs.isRunning(entry.id) {
            runs.cancel(entry.id)
        } else {
            runs.start(entry.id) { [weak self] outcome in self?.finished(entry, outcome) }
        }
    }

    private func finished(_ entry: ShortcutEntry, _ outcome: ShortcutRunOutcome) {
        switch outcome {
        case .succeeded:
            announce(String(localized: "\(entry.displayName) finished", bundle: .module,
                            comment: "Quick Apps: VoiceOver announcement after a shortcut ran (shortcut name)"))
            if showsResultInNotch(entry) {
                notch.flash(symbol: "checkmark.circle.fill",
                            label: String(localized: "Done", bundle: .module, comment: "Notch flash after a shortcut ran (≤ 12 characters)"))
            }
        case .failed:
            announce(String(localized: "\(entry.displayName) failed", bundle: .module,
                            comment: "Quick Apps: VoiceOver announcement after a shortcut failed (shortcut name)"))
            if showsResultInNotch(entry) {
                notch.flash(symbol: "exclamationmark",
                            label: String(localized: "Failed", bundle: .module, comment: "Notch flash after a shortcut failed (≤ 12 characters)"))
            }
            // A deleted shortcut fails too: re-read the list once to say so.
            Task {
                await shortcutsCatalog.refresh()
                if shortcutsCatalog.hasLoaded, shortcutsCatalog.info(for: entry.id) == nil {
                    runs.replaceFailure(of: entry.id, with: .shortcutNotFound)
                }
            }
        case .cancelled:
            break
        }
    }

    /// A tile shows its own result while the panel is open; otherwise (panel closed, or a shortcut run from ⌘K
    /// that has no tile) the notch flashes it.
    private func showsResultInNotch(_ entry: ShortcutEntry) -> Bool {
        !isPanelOpen || !isAdded(shortcut: entry.id)
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    /// Keeps tile names in step with Shortcuts.app (a renamed shortcut keeps its tile: it runs by identifier).
    private func syncNames(with list: [ShortcutInfo]) {
        let names = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var entries = shortcutEntries
        var changed = false
        for index in entries.indices {
            if let name = names[entries[index].id], name != entries[index].name {
                entries[index].name = name
                changed = true
            }
        }
        if changed { settings[QuickAppsSettings.shortcuts] = entries }
    }

    // MARK: - Navigation

    func openSettings() { appControl.openSettings(.shortcuts) }
}
