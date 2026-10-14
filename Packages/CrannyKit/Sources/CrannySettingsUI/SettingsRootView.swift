// CrannySettingsUI/SettingsRootView.swift — the Settings window content (DESIGN.md §11), WP14.
// WP0 skeleton: the sidebar with every shell pane plus the registry's module panes, grouped and searchable;
// placeholder detail panes. WP14 adds the preview stage, every pane and the reset conventions.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

/// The Settings window's content (DESIGN.md §11): sidebar of shell and module panes, search, detail pane.
public struct SettingsRootView: View {
    private let registry: ModuleRegistry
    @State private var selection: SettingsPageID?
    @State private var query = ""

    /// Opens on `initialPage` (General when nil).
    public init(registry: ModuleRegistry, initialPage: SettingsPageID? = nil) {
        self.registry = registry
        _selection = State(initialValue: initialPage ?? .general)
    }

    /// Shell panes + module panes, ordered by group then order (§11.1).
    var pages: [SettingsPage] {
        (ShellPanes.all(registry: registry) + registry.settingsPages).sorted { ($0.group, $0.order) < ($1.group, $1.order) }
    }

    public var body: some View {
        let visible = SettingsSearch.filter(pages, query: query)
        NavigationSplitView {
            SettingsSidebar(pages: visible, selection: $selection)
                .searchable(text: $query, placement: .sidebar)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            if let page = pages.first(where: { $0.id == selection }) {
                page.makeView()
                    .navigationTitle(Text(verbatim: page.title))
            }
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}

/// Matches pane titles and their localized keywords (module panes list their row labels, §3.7).
enum SettingsSearch {
    static func filter(_ pages: [SettingsPage], query: String) -> [SettingsPage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pages }
        return pages.filter { page in
            page.title.localizedCaseInsensitiveContains(q) || page.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}

#Preview("Settings") {
    SettingsRootView(registry: ModuleRegistry(services: .preview()))
        .frame(width: 860, height: 620)
        .background(.black)
        .preferredColorScheme(.dark)
        .crannyThemeRoot(CrannyTheme())
}
