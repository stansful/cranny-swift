// CrannyNotchUI/Nook/NookHeader.swift — the header row in the band (DESIGN.md §6.2): page tabs left of the
// camera, the empty camera zone (time and date on displays without a notch), actions on the right.
// WP0 skeleton; WP12 adds badges, collapsing titles, matched-geometry selection, hold-⌘ hints and the
// ⌕ Command palette button (⌘K), which ships with the palette itself (DESIGN.md §6.2, §6.4).
import CrannyCore
import Foundation
import SwiftUI

struct NookHeader: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let layout = model.layout
        HStack(spacing: 0) {
            tabs.frame(maxWidth: .infinity, alignment: .leading)
            if layout.metrics.hasNotch {
                Color.clear.frame(width: layout.middle() + 16)                 // never draw over the camera
            } else {
                clock.fixedSize().padding(.horizontal, Space.m)
            }
            buttons.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: Tabs

    private struct Tab: Identifiable {
        let id: PageID
        let title: String
        let symbol: String
    }

    private var tabItems: [Tab] {
        let gridPages = registry.services.settings[CoreSettings.pages].map { page in
            Tab(id: page.id, title: page.title ?? String(localized: "Home", bundle: .module, comment: "Open panel: the built-in widget page (tab)"),
                symbol: page.symbol)
        }
        let modulePages = registry.pages.sorted { $0.order < $1.order }.map { Tab(id: $0.id, title: $0.title, symbol: $0.symbol) }
        return gridPages + modulePages
    }

    /// Visual height of a tab segment (DESIGN.md §6.2).
    static let segmentHeight: CGFloat = 22
    /// How far the tap area reaches beyond the segment so it is ≥ 24 pt tall (DESIGN.md §16).
    static let hitOutset = max(0, (HitTarget.band.height - segmentHeight) / 2)

    private var tabs: some View {
        let p = theme.palette
        let selected = model.open?.page ?? .nook
        return HStack(spacing: Space.xxs) {
            ForEach(tabItems) { tab in
                Button { actions.selectPage(tab.id) } label: {
                    Label { Text(verbatim: tab.title) } icon: { Image(systemName: tab.symbol) }
                        .labelStyle(.titleAndIcon)
                        .crannyFont(.headline)
                        .lineLimit(1)
                        .foregroundStyle(tab.id == selected ? p.label : p.secondaryLabel)
                        .padding(.horizontal, Space.m + 2)
                        .frame(minWidth: HitTarget.band.width)
                        .frame(height: Self.segmentHeight)
                        .background { if tab.id == selected { Capsule(style: .continuous).fill(p.controlPressed) } }
                        // The segment is 22 pt (DESIGN.md §6.2); the hit target reaches 24 pt (§16, band) into the
                        // track's inset without changing the layout.
                        .contentShape(Rectangle().inset(by: -Self.hitOutset))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab.id == selected ? .isSelected : [])
            }
        }
        .padding(Space.xxs)
        .background(Capsule(style: .continuous).fill(p.control))
    }

    // MARK: Centre (displays without a notch)

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                .crannyFont(.eyebrow)
                .foregroundStyle(theme.palette.secondaryLabel)
        }
    }

    // MARK: Actions

    private var buttons: some View {
        HStack(spacing: Space.xs) {
            Button(action: actions.togglePin) { Image(systemName: model.pinned ? "pin.fill" : "pin") }
                .buttonStyle(CrannyIconButtonStyle(model.pinned ? .filled : .plain))
                .accessibilityLabel(Text("Keep Cranny open", bundle: .module, comment: "Open panel: pin button (⌘P)"))
                .accessibilityAddTraits(model.pinned ? .isSelected : [])
                .help(String(localized: "Keep Cranny open", bundle: .module, comment: "Open panel: pin button (⌘P)"))
            Button(action: actions.openSettings) { Image(systemName: "gearshape.fill") }
                .buttonStyle(CrannyIconButtonStyle(.plain))
                .accessibilityLabel(Text("Settings", bundle: .module, comment: "Open panel: header button (⌘,)"))
                .help(String(localized: "Settings", bundle: .module, comment: "Open panel: header button (⌘,)"))
        }
    }
}

#Preview("Header · Home selected") {
    let (model, registry) = previewScene(.open)
    NookHeader(model: model, registry: registry, actions: NotchUIActions())
        .frame(width: model.layout.open(columns: model.openColumns).bodyWidth - 2 * Space.l, height: model.layout.headerHeight)
        .padding(.horizontal, Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
