// CrannySettingsUI/SettingsSession.swift — the Settings window's state, owned by the window controller so it outlives
// the views and the window itself: the pane shown (and a row to reveal), the search text and the sidebar's pick, the
// 10-s Undo offer of Reset All and the preview stage. Opening a pane on a window that is already open navigates this
// state; nothing is rebuilt, so the Undo offer, the search and the stage survive a deep link, a ⌘K pane command or the
// menu bar (DESIGN.md §11.1, §11.3). Closing Settings releases the window and its views (`windowDidClose()`); the next
// open builds them around the same session, so only pane-local view state (scroll positions, a pane's own picks)
// starts fresh.
import CrannyCore
import Foundation
import Observation

/// The state behind the Settings window. Create it once and pass it to every `SettingsRootView(session:)` built for
/// the window.
@MainActor @Observable public final class SettingsSession {
    let registry: ModuleRegistry
    let navigator: SettingsNavigator
    let resetAll: ResetAllController
    let stage: StageController
    /// The search index, built on the first query and again only when the panes or rows change.
    let searchIndex = SearchIndexCache()
    /// The sidebar's search text (Debug QA may start it with one, `SettingsQAOptions`).
    var query = SettingsQAOptions.search ?? ""
    /// The sidebar row picked: a pane, or a setting the search found.
    var sidebarSelection: SidebarItem?
    /// The pane the stage last took its state for: a window rebuilt on that pane keeps the state picked there.
    @ObservationIgnored var stagedPane: SettingsPageID

    /// Opens on `initialPage` ("pane" or "pane#row"; General when nil).
    public init(registry: ModuleRegistry, initialPage: SettingsPageID? = nil) {
        self.registry = registry
        let navigator = SettingsNavigator(target: initialPage)
        self.navigator = navigator
        resetAll = ResetAllController(settings: registry.services.settings, app: registry.services.app)
        let shown = SettingsRootView.pages(registry: registry).first { $0.id == navigator.selection }
        stage = StageController(registry: registry, state: SettingsRootView.stageState(for: shown))
        sidebarSelection = .pane(navigator.selection)
        stagedPane = navigator.selection
    }

    /// Shows `page` ("pane" or "pane#row", which also scrolls to the row and highlights it); nil keeps the pane.
    public func open(_ page: SettingsPageID?) { navigator.open(page) }

    /// The pane on screen.
    public var currentPage: SettingsPageID { navigator.selection }

    /// The window closed and its views are gone: the stage stops (its view may not get to stop it) and lets go of the
    /// wallpaper miniature, decoded again when the stage next appears. The pane, the search and the Undo offer stay.
    public func windowDidClose() {
        stage.stop()
        stage.wallpaper = nil
        WallpaperSource.purge()
    }
}

/// The search index for the current panes and rows. Building it folds every row label and keyword, so the root view
/// asks for it only while a query is typed and reuses it until something it indexes changes.
@MainActor final class SearchIndexCache {
    private var index: SettingsSearchIndex?
    private var signature: [String] = []

    /// The index of `pages` and `rows()`; `signature` names what they depend on (it is cheap to compute, the rows
    /// are not).
    func index(pages: [SettingsPage], signature: [String], rows: () -> [SettingsRowInfo]) -> SettingsSearchIndex {
        if let index, signature == self.signature { return index }
        let built = SettingsSearchIndex(pages: pages, rows: rows(), aliases: KnownPaneKeywords.all)
        index = built
        self.signature = signature
        return built
    }
}
