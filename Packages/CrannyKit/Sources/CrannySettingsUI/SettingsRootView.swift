// CrannySettingsUI/SettingsRootView.swift — the Settings window content (DESIGN.md §11): a `NavigationSplitView` with
// the searchable sidebar of shell and module panes, the live preview stage pinned above every pane that has one,
// the pane itself and its "Reset ‹Pane›…" footer, and the 10-s Undo banner after Reset All. Its state lives in a
// `SettingsSession`, which the window controller keeps and navigates.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// The Settings window's content (DESIGN.md §11): sidebar of shell and module panes, search, preview stage, pane.
public struct SettingsRootView: View {
    private let onPageChange: (@MainActor (SettingsPageID) -> Void)?
    @State private var session: SettingsSession
    @State private var query = ""
    @State private var sidebarSelection: SidebarItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opens on `initialPage` (General when nil). A deep link "pane#row" (e.g. `general#hoverDelay`) also scrolls to
    /// and highlights that row. `onPageChange` reports the pane shown, so the window can restore it next time.
    public init(registry: ModuleRegistry, initialPage: SettingsPageID? = nil,
                onPageChange: (@MainActor (SettingsPageID) -> Void)? = nil) {
        self.init(session: SettingsSession(registry: registry, initialPage: initialPage), onPageChange: onPageChange)
    }

    /// Shows `session`, which the caller keeps to navigate the open window (`SettingsSession.open(_:)`).
    public init(session: SettingsSession, onPageChange: (@MainActor (SettingsPageID) -> Void)? = nil) {
        self.onPageChange = onPageChange
        _session = State(initialValue: session)
        _sidebarSelection = State(initialValue: .pane(session.navigator.selection))
        _query = State(initialValue: SettingsQAOptions.search ?? "")
    }

    private var registry: ModuleRegistry { session.registry }
    private var navigator: SettingsNavigator { session.navigator }
    private var resetAll: ResetAllController { session.resetAll }
    private var stage: StageController { session.stage }

    /// Shell panes + module panes, ordered by group then order (§11.1).
    var pages: [SettingsPage] { Self.pages(registry: registry) }

    static func pages(registry: ModuleRegistry) -> [SettingsPage] {
        (ShellPanes.all(registry: registry) + registry.settingsPages).sorted { ($0.group, $0.order) < ($1.group, $1.order) }
    }

    public var body: some View {
        let pages = self.pages
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationSplitView {
            SettingsSidebar(pages: pages, results: trimmed.isEmpty ? nil : searchIndex(pages).search(trimmed), selection: $sidebarSelection)
                .searchable(text: $query, placement: .sidebar,
                            prompt: Text("Search", bundle: .module, comment: "Settings sidebar: search field placeholder"))
                .navigationSplitViewColumnWidth(min: SettingsMetrics.sidebarWidth.min, ideal: SettingsMetrics.sidebarWidth.ideal,
                                                max: SettingsMetrics.sidebarWidth.max)
        } detail: {
            if let page = pages.first(where: { $0.id == navigator.selection }) ?? pages.first {
                PaneContainer(page: page, registry: registry, stage: stage)
                    .navigationTitle(Text(verbatim: page.title))
            }
        }
        .overlay(alignment: .bottom) {
            if resetAll.canUndo {
                UndoBanner(controller: resetAll)
                    .padding(.bottom, 60)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))   // no slide (DESIGN §16)
            }
        }
        .animation(CrannyMotion.animation(.contentSwap, reduceMotion: reduceMotion), value: resetAll.canUndo)
        .environment(navigator)
        .environment(resetAll)
        .environment(stage)
        .frame(minWidth: SettingsMetrics.minimumWindowSize.width, minHeight: SettingsMetrics.minimumWindowSize.height)
        .onChange(of: sidebarSelection) { _, item in
            switch item {
            case .pane(let id)?: navigator.open(id)
            case .row(let row)?: navigator.open(row: row)
            case nil: break
            }
        }
        .onChange(of: navigator.selection, initial: true) { _, selection in
            if !Self.item(sidebarSelection, points: selection) { sidebarSelection = .pane(selection) }
            stage.select(Self.stageState(for: pages.first { $0.id == selection }))
            onPageChange?(selection)
        }
        .onChange(of: trimmed.isEmpty) { _, isEmpty in
            if isEmpty { sidebarSelection = .pane(navigator.selection) }
        }
    }

    /// The index for a query: rebuilt only when the panes, the registered rows or an Automation app (its name, or
    /// whether it is installed) change.
    private func searchIndex(_ pages: [SettingsPage]) -> SettingsSearchIndex {
        let signature = pages.map(\.id.rawValue)
            + [registry.shortcuts.count, registry.widgets.count, registry.activities.count, registry.permissionUses.count,
               AppIdentityResolver.shared.revision].map(String.init)
        return session.searchIndex.index(pages: pages, signature: signature) { ShellPanes.rows(registry: registry) }
    }

    /// The state the stage auto-selects for a pane (Debug QA may pin one, `SettingsQAOptions`).
    static func stageState(for page: SettingsPage?) -> PreviewStageState {
        SettingsQAOptions.stageState ?? StageScript.initialState(for: page)
    }

    /// The sidebar item already shows `pane` (its own row, or a search hit inside it).
    private static func item(_ item: SidebarItem?, points pane: SettingsPageID) -> Bool {
        switch item {
        case .pane(let id)?: id == pane
        case .row(let row)?: row.pane == pane
        case nil: false
        }
    }
}

/// The detail column: the stage (if the pane has one), the pane and its reset footer.
private struct PaneContainer: View {
    let page: SettingsPage
    let registry: ModuleRegistry
    let stage: StageController

    var body: some View {
        VStack(spacing: 0) {
            if page.previewState != nil {
                PreviewStage(controller: stage, registry: registry)
            }
            page.makeView()
                .id(page.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !page.namespaces.isEmpty {
                        PaneFooter(page: page, settings: registry.services.settings)
                    }
                }
        }
    }
}

#Preview("Settings") {
    SettingsRootView(registry: ModuleRegistry(services: .preview()))
        .frame(width: 860, height: 620)
}

#Preview("Settings · session") {
    let session = SettingsSession(registry: ModuleRegistry(services: .preview()), initialPage: .appearance)
    SettingsRootView(session: session)
        .frame(width: 860, height: 620)
}

#Preview("Settings · deep link") {
    SettingsRootView(registry: ModuleRegistry(services: .preview()), initialPage: "general#hoverDelay")
        .frame(width: 860, height: 620)
}
