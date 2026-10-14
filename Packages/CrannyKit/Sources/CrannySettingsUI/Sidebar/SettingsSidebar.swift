// CrannySettingsUI/Sidebar/SettingsSidebar.swift — the sidebar (DESIGN.md §11.1): one section per group,
// each row a 20 × 20 rounded-square icon (r 5, continuous) with a white glyph on a system colour.
import CrannyCore
import SwiftUI

struct SettingsSidebar: View {
    let pages: [SettingsPage]
    @Binding var selection: SettingsPageID?

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.self) { group in
                Section {
                    ForEach(pages.filter { $0.group == group }) { page in
                        Label {
                            Text(verbatim: page.title)
                        } icon: {
                            SidebarIcon(symbol: page.symbol, tint: page.tint)
                        }
                        .tag(page.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var groups: [SettingsGroup] {
        var seen: [SettingsGroup] = []
        for page in pages where !seen.contains(page.group) { seen.append(page.group) }
        return seen
    }
}

struct SidebarIcon: View {
    let symbol: String
    let tint: SettingsIconTint
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.color.gradient))
            .accessibilityHidden(true)
    }
}
