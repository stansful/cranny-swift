// CrannySettingsUI/SettingsSession.swift — the Settings window's state, owned by the window controller so it outlives
// the views: the pane shown (and a row to reveal), the 10-s Undo offer of Reset All and the preview stage. Opening a
// pane on a window that is already open navigates this state; nothing is rebuilt, so the Undo offer, the search and
// the stage survive a deep link, a ⌘K pane command or the menu bar (DESIGN.md §11.1, §11.3).
import CrannyCore
import Foundation

/// The state behind one Settings window. Create it once per window and pass it to `SettingsRootView(session:)`.
@MainActor public final class SettingsSession {
    let registry: ModuleRegistry
    let navigator: SettingsNavigator
    let resetAll: ResetAllController
    let stage: StageController
    /// The search index, built on the first query and again only when the panes or rows change.
    let searchIndex = SearchIndexCache()

    /// Opens on `initialPage` ("pane" or "pane#row"; General when nil).
    public init(registry: ModuleRegistry, initialPage: SettingsPageID? = nil) {
        self.registry = registry
        let navigator = SettingsNavigator(target: initialPage)
        self.navigator = navigator
        resetAll = ResetAllController(settings: registry.services.settings, app: registry.services.app)
        let shown = SettingsRootView.pages(registry: registry).first { $0.id == navigator.selection }
        stage = StageController(registry: registry, state: SettingsRootView.stageState(for: shown))
    }

    /// Shows `page` ("pane" or "pane#row", which also scrolls to the row and highlights it); nil keeps the pane.
    public func open(_ page: SettingsPageID?) { navigator.open(page) }

    /// The pane on screen.
    public var currentPage: SettingsPageID { navigator.selection }
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
