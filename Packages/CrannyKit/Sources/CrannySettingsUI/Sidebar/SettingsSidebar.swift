// CrannySettingsUI/Sidebar/SettingsSidebar.swift — the sidebar (DESIGN.md §11.1): one section per group, each row a
// 20 × 20 rounded-square icon (r 5, continuous) with a white glyph on a system colour. While searching it lists the
// matching panes and, below them, the matching settings with their pane; picking one opens the pane at that row.
import CrannyCore
import Foundation
import SwiftUI

/// What a sidebar row points at.
enum SidebarItem: Hashable {
    case pane(SettingsPageID)
    case row(SettingsRowInfo)
}

struct SettingsSidebar: View {
    /// Every pane in sidebar order.
    let pages: [SettingsPage]
    /// nil while the search field is empty.
    let results: SettingsSearchIndex.Results?
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            if let results {
                searchResults(results)
            } else {
                ForEach(groups, id: \.self) { group in
                    Section {
                        ForEach(pages.filter { $0.group == group }) { page in
                            PaneLabel(page: page).tag(SidebarItem.pane(page.id))
                        }
                    } header: {
                        if let title = Self.title(of: group) { Text(verbatim: title) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private func searchResults(_ results: SettingsSearchIndex.Results) -> some View {
        if results.isEmpty {
            Text("No results", bundle: .module, comment: "Settings sidebar: the search found nothing")
                .foregroundStyle(.secondary)
                .selectionDisabled()
        } else {
            Section {
                ForEach(results.panes, id: \.self) { id in
                    if let page = pages.first(where: { $0.id == id }) {
                        PaneLabel(page: page).tag(SidebarItem.pane(page.id))
                    }
                }
            }
            if !results.rows.isEmpty {
                Section {
                    ForEach(results.rows) { row in
                        if let page = pages.first(where: { $0.id == row.pane }) {
                            RowResultLabel(row: row, page: page).tag(SidebarItem.row(row))
                        }
                    }
                } header: {
                    Text("Settings", bundle: .module, comment: "Settings sidebar: header above the settings (rows) a search found")
                }
            }
        }
    }

    private var groups: [SettingsGroup] {
        var seen: [SettingsGroup] = []
        for page in pages where !seen.contains(page.group) { seen.append(page.group) }
        return seen
    }

    /// The top and bottom groups have no header (DESIGN.md §11.1).
    static func title(of group: SettingsGroup) -> String? {
        switch group {
        case .top, .bottom: nil
        case .notch: String(localized: "Notch", bundle: .module, comment: "Settings sidebar: group header (Layout & Widgets, Live Activities, HUD, Gestures)")
        case .features: String(localized: "Features", bundle: .module, comment: "Settings sidebar: group header (Media, Calendar, Shortcuts, Tray)")
        }
    }
}

/// A pane row: icon and name.
struct PaneLabel: View {
    let page: SettingsPage
    var body: some View {
        Label {
            Text(verbatim: page.title)
        } icon: {
            SidebarIcon(symbol: page.symbol, tint: page.tint)
        }
    }
}

/// A search hit on a row: the row's label with its pane's icon and name below.
struct RowResultLabel: View {
    let row: SettingsRowInfo
    let page: SettingsPage
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.title).lineLimit(1)
                Text(verbatim: page.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            SidebarIcon(symbol: page.symbol, tint: page.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 20 × 20 rounded square (r 5, continuous), white glyph on a system colour, as in System Settings.
struct SidebarIcon: View {
    let symbol: String
    let tint: SettingsIconTint
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: SettingsMetrics.sidebarGlyph, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: SettingsMetrics.sidebarIcon, height: SettingsMetrics.sidebarIcon)
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.sidebarIconRadius, style: .continuous)
                .fill(tint.color.gradient))
            .accessibilityHidden(true)
    }
}

#Preview("Sidebar · shell panes") {
    @Previewable @State var selection: SidebarItem? = .pane(.general)
    SettingsSidebar(pages: ShellPanes.all(registry: ModuleRegistry(services: .preview())), results: nil, selection: $selection)
        .frame(width: 210, height: 420)
}

#Preview("Sidebar · search") {
    @Previewable @State var selection: SidebarItem?
    let pages = ShellPanes.all(registry: ModuleRegistry(services: .preview()))
    let index = SettingsSearchIndex(pages: pages, rows: ShellPanes.rows(registry: ModuleRegistry(services: .preview())))
    SettingsSidebar(pages: pages, results: index.search("hover"), selection: $selection)
        .frame(width: 210, height: 420)
}
