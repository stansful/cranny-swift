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
    /// Whether the open panel is pinned (from `NotchEvent.pinned`): opening an app then leaves it open.
    private(set) var isPinned = false

    /// Posts a VoiceOver announcement (tests record them instead).
    @ObservationIgnored var announce: @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    @ObservationIgnored private var announcements = AnnouncementLimiter()
    /// The tiles each launcher on screen shows as tiles (not in "+N"), per launcher view (`present(_:by:)`).
    @ObservationIgnored private var presentedTiles: [UUID: Set<TileID>] = [:]
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
        case .pinned(let pinned):
            isPinned = pinned
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

    /// Opens the app. The panel closes at once, like a menu (a cold launch can take a second and the panel should
    /// not sit there meanwhile), unless it is pinned or in Demo mode: both keep it open (ARCHITECTURE.md §4.4–§4.5).
    /// A failure flashes in the notch and re-checks which apps are installed.
    func open(_ app: ResolvedApp) {
        if !isPinned && !environment.isDemoMode { notch.close() }
        Task {
            do {
                try await launcher.open(app.url)
            } catch {
                log.error("could not open \(app.bundleID, privacy: .public)")
                notch.flash(symbol: "exclamationmark", label: Self.failedLabel)
                await catalog.refresh(appEntries.map(\.bundleID))
            }
        }
    }

    /// The notch flash after a failure (≤ 12 characters).
    static var failedLabel: String {
        String(localized: "Failed", bundle: .module, comment: "Notch flash: a shortcut or an app failed (≤ 12 characters)")
    }

    /// The name of a shortcut wherever it could be seen or heard; neutral in Demo mode (it may be personal).
    func publicName(of entry: ShortcutEntry) -> String {
        environment.isDemoMode ? Self.neutralShortcutName : entry.displayName
    }

    static var neutralShortcutName: String {
        String(localized: "Shortcut", bundle: .module, comment: "Quick Apps: a Shortcuts.app shortcut (⌘K result kind, Settings row subtitle, neutral tile name in Demo mode)")
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
            reportInNotch(entry, symbol: "checkmark.circle.fill",
                          label: String(localized: "Done", bundle: .module, comment: "Notch flash: a shortcut finished (≤ 12 characters)"),
                          announcement: String(localized: "\(publicName(of: entry)) finished", bundle: .module,
                                               comment: "Quick Apps: VoiceOver announcement after a shortcut ran (shortcut name)"))
        case .failed:
            reportInNotch(entry, symbol: "exclamationmark", label: Self.failedLabel,
                          announcement: String(localized: "\(publicName(of: entry)) failed", bundle: .module,
                                               comment: "Quick Apps: VoiceOver announcement after a shortcut failed (shortcut name)"))
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

    /// A result nobody can see on a tile — the panel is closed, the tile is in "+N" or on a page that is not shown,
    /// or the shortcut ran from ⌘K and has no tile — flashes in the notch and, at most once per 10 s, is announced
    /// to VoiceOver (DESIGN.md §16). A tile on screen shows the result itself and in its accessibility value.
    private func reportInNotch(_ entry: ShortcutEntry, symbol: String, label: String, announcement: String) {
        guard !isOnScreenAsTile(.shortcut(entry.id)) else { return }
        notch.flash(symbol: symbol, label: label)
        if announcements.allows(at: Date()) { announce(announcement) }
    }

    // MARK: - Tiles on screen

    /// A launcher view reports which tiles it shows as tiles (not in "+N"), whenever that changes.
    func present(_ tiles: Set<TileID>, by launcher: UUID) {
        presentedTiles[launcher] = tiles
    }

    /// A launcher view left the screen (closed panel, another page, another layout).
    func withdrawTiles(of launcher: UUID) {
        presentedTiles[launcher] = nil
    }

    /// Whether the open panel shows this tile, so the tile itself shows its run state.
    func isOnScreenAsTile(_ id: TileID) -> Bool {
        isPanelOpen && presentedTiles.values.contains { $0.contains(id) }
    }

    /// Reads the Shortcuts list ahead of the add menu (hover or focus on "+", the menu opening). Skipped when
    /// it was read within the last minute.
    func prepareShortcutList() {
        Task { await shortcutsCatalog.refresh(maximumAge: 60) }
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
