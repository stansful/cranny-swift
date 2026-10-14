// CrannyNotchUI/Nook/NookView.swift — the open panel: the light layer, the header in the band and the page
// (DESIGN.md §6.1–§6.3). WP0 skeleton: grid pages from `CoreSettings.pages`, module pages from the registry,
// placeholder cards for widgets whose module is not built yet. WP12 adds palette, edit mode, focus, catch.
import CrannyCore
import CrannyEffects
import Foundation
import SwiftUI

struct NookView: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let layout = model.layout
        let shape = finalShape
        let grid = theme.grid
        ZStack(alignment: .top) {
            if theme.effectiveAmbience != .off {
                AuroraField(palette: model.ambient, level: theme.effectiveAmbience,
                            energy: registry.services.nowPlaying?.audioEnergy ?? 0,
                            budget: registry.services.environment.effectBudget(
                                isOpen: model.phase == .open, isOnScreen: true,
                                reduceMotion: theme.reduceMotion || theme.motion == .instant))
                    .frame(width: shape.bodyWidth, height: shape.height)
                    .transition(.opacity.animation(theme.animation(.ambientIn)))
            }
            VStack(spacing: grid.headerGap) {
                NookHeader(model: model, registry: registry, actions: actions)
                    .frame(height: layout.headerHeight)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, grid.padding)
            .padding(.bottom, grid.padding)
            .frame(width: shape.bodyWidth, height: shape.height, alignment: .top)
        }
        .frame(width: shape.bodyWidth, height: shape.height, alignment: .top)
        .padding(.top, shape.topInset)
        .foregroundStyle(theme.palette.label)
    }

    /// Content is laid out at the FINAL open size and revealed by the clip (no reflow during the morph).
    private var finalShape: NotchGeometry {
        if case .focus? = model.open?.mode { return model.layout.open(columns: model.layout.maxColumns, rows: 3) }
        return model.layout.open(columns: model.openColumns)
    }

    @ViewBuilder private var page: some View {
        let pageID = model.open?.page ?? .nook
        let pages = registry.services.settings[CoreSettings.pages]
        if let gridPage = pages.first(where: { $0.id == pageID }) {
            GridPage(page: gridPage, model: model, registry: registry)
        } else if let modulePage = registry.pages.first(where: { $0.id == pageID }) {
            modulePage.makeView(WidgetContext(cells: model.openColumns, contentSize: CGSize(
                width: theme.grid.width(cells: model.openColumns), height: theme.grid.height),
                isPreview: model.context.isPreview, redactsPersonalData: model.context.redactsPersonalData))
        } else {
            PlaceholderPage(symbol: pageID == .tray ? "tray.full.fill" : "square.grid.2x2.fill")
        }
    }
}

/// A row of cards (2 rows tall), centred under the camera.
private struct GridPage: View {
    @Environment(\.cranny) private var theme
    let page: NookPage
    let model: NotchSceneModel
    let registry: ModuleRegistry

    var body: some View {
        HStack(spacing: theme.grid.gutter) {
            ForEach(page.items, id: \.widget) { item in
                WidgetCard(item: item, registry: registry, context: model.context)
            }
        }
    }
}

/// A page whose module is not built yet (e.g. `--qa-page tray` before WP8).
private struct PlaceholderPage: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    var body: some View {
        WidgetStateView(.empty, symbol: symbol,
                        message: String(localized: "Nothing here yet", bundle: .module, comment: "Open panel: page placeholder"))
            .frame(height: theme.grid.height)
    }
}

#Preview("Open panel · Home") {
    let (model, registry) = previewScene(.open)
    let shape = model.layout.open(columns: model.openColumns)
    NookView(model: model, registry: registry, actions: NotchUIActions())
        .frame(width: shape.bodyWidth, height: shape.height + shape.topInset)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
