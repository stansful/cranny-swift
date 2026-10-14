// CrannyNotchUI/Nook/NookView.swift — the open panel (DESIGN.md §6.1): the header in the band, a 6-pt gap,
// then the grid area — a grid page, a module page (the Tray), the ⌘K palette, the layout editor, Notes focus or
// the drag catch zones — inside the panel padding. Content is laid out at the FINAL open size and revealed by
// the clip (no reflow during the morph); the header enters first (`contentIn`), then the widgets radiate out
// from the camera. The light layer behind it is drawn by the canvas (`NookLightLayer`).
import CrannyCore
import Foundation
import SwiftUI

struct NookView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    /// Direction of the last tab change, set one update BEFORE the page changes so the leaving page and the
    /// arriving page slide the same way (a removed view keeps the transition of its last update).
    @State private var forward = true
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        let shape = NookView.finalShape(model)
        let grid = theme.grid
        VStack(spacing: grid.headerGap) {
            NookHeader(model: model, registry: registry, actions: actions, select: select, perform: perform)
                .frame(height: model.layout.headerHeight)
                .staggeredReveal(delay: 0)
            pageArea
                .frame(width: shape.bodyWidth - 2 * grid.padding, height: NookView.gridAreaHeight(model, grid: grid))
                .background { if needsScrim { scrim.transition(.opacity.animation(theme.animation(.contentSwap))) } }
        }
        .padding(.horizontal, grid.padding)
        .padding(.bottom, grid.padding)
        .frame(width: shape.bodyWidth, height: shape.height, alignment: .top)
        .padding(.top, shape.topInset)
        .foregroundStyle(theme.palette.label)
        .background { NookHiddenShortcuts(perform: perform) }
        .onAppear {
            AccessibilityNotification.LayoutChanged().post()                // VoiceOver lands in the opened panel
            if let qa = NotchUIQAHooks.mode, !NotchUIQAHooks.didApplyMode, !context.isPreview {   // DEBUG-only visual QA
                NotchUIQAHooks.didApplyMode = true
                Task { @MainActor in actions.setMode(qa) }
            }
        }
    }

    // MARK: Geometry

    /// The open shape at rest (Notes focus: all columns × 3 rows).
    static func finalShape(_ model: NotchSceneModel) -> NotchGeometry {
        if case .focus? = model.open?.mode { return model.layout.open(columns: model.layout.maxColumns, rows: 3) }
        return model.layout.open(columns: model.openColumns)
    }

    /// The grid area: 2 rows (3 in Notes focus).
    static func gridAreaHeight(_ model: NotchSceneModel, grid: NookGrid) -> CGFloat {
        var g = grid
        if case .focus? = model.open?.mode { g.rows = 3 }
        return g.height
    }

    // MARK: Pages

    private var mode: NookMode { model.open?.mode ?? .grid }
    private var pageID: PageID { model.open?.page ?? .nook }
    private var gridPage: NookPage? { registry.services.settings[CoreSettings.pages].first { $0.id == pageID } }
    private var tabs: [HeaderTab] {
        HeaderTabItems.make(pages: registry.services.settings[CoreSettings.pages], modulePages: registry.pages)
    }
    private var pageIndex: Int { tabs.firstIndex { $0.id == pageID } ?? 0 }

    @ViewBuilder private var pageArea: some View {
        let swap = AnyTransition.opacity.animation(theme.animation(.contentSwap))
        switch mode {
        case .palette:
            CommandPaletteView(registry: registry, height: NookView.gridAreaHeight(model, grid: theme.grid),
                               setMode: actions.setMode)
                .transition(swap)
        case .editLayout where gridPage != nil:
            if let gridPage {
                EditLayoutView(page: gridPage, model: model, registry: registry, actions: actions)
                    .transition(swap)
            }
        case .focus(let widget):
            FocusedWidgetPage(widget: widget, model: model, registry: registry)
        case .catchFiles(let types):
            CatchHost(types: types, registry: registry)
                .transition(swap)
        default:
            page
                .id(pageID)
                .transition(.crannyTab(forward: forward, reduceMotion: theme.reduceMotion)
                    .animation(theme.animation(.tab)))
        }
    }

    @ViewBuilder private var page: some View {
        if let gridPage {
            WidgetGridPage(page: gridPage, model: model, registry: registry, actions: actions)
        } else if let modulePage = registry.pages.first(where: { $0.id == pageID }) {
            modulePage.makeView(WidgetContext(
                cells: model.openColumns, rows: theme.grid.rows,
                contentSize: CGSize(width: theme.grid.width(cells: model.openColumns), height: theme.grid.height),
                isPreview: context.isPreview, redactsPersonalData: context.redactsPersonalData))
            .staggeredReveal(delay: 0)
        } else {
            PlaceholderPage(symbol: pageID == .tray ? "tray.full.fill" : "square.grid.2x2.fill", columns: model.openColumns)
        }
    }

    /// Light never sits behind text without a card or a scrim (DESIGN.md §5): the flat style (§6.3), the palette
    /// and the catch zones draw text straight on the grid area, so it gets a scrim while the light is on.
    private var needsScrim: Bool {
        guard theme.effectiveAmbience != .off else { return false }
        switch mode {
        case .palette, .catchFiles: return true
        default: return theme.widgetStyle == .flat
        }
    }

    private var scrim: some View {
        RoundedRectangle(cornerRadius: theme.grid.cardRadius, style: .continuous).fill(theme.palette.scrim)
    }

    // MARK: Commands (keys and header buttons)

    /// Tabs, ⌘1–⌘5 and ⌃Tab: set the slide direction now, change the page on the next turn of the run loop.
    private func select(_ page: PageID) {
        guard page != pageID else { return }
        forward = (tabs.firstIndex { $0.id == page } ?? 0) >= pageIndex
        Task { @MainActor in actions.selectPage(page) }
    }

    private func perform(_ command: NookCommand) {
        switch command {
        case .togglePalette:
            actions.setMode(mode == .palette ? .grid : .palette)
        case .togglePin:
            actions.togglePin()
        case .toggleEditLayout:
            guard gridPage != nil else { return }
            actions.setMode(mode == .editLayout ? .grid : .editLayout)
        case .openSettings:
            actions.openSettings()
        case .selectPage(let index):
            if tabs.indices.contains(index) { select(tabs[index].id) }
        case .nextPage, .previousPage:
            if let next = NookKeyMap.page(after: pageID, in: tabs.map(\.id), forward: command == .nextPage) {
                select(next)
            }
        case .escape:
            if let back = NookKeyMap.escape(from: mode) { actions.setMode(back) } else { actions.close() }
        }
    }
}

/// A page that disappeared while the panel was open (its module or user page went away). The shell opens
/// only pages that exist, so this is a fallback, never a destination.
private struct PlaceholderPage: View {
    @Environment(\.cranny) private var theme
    let symbol: String
    let columns: Int
    var body: some View {
        WidgetStateView(.empty, symbol: symbol,
                        message: String(localized: "Nothing here yet", bundle: .module, comment: "Open panel: placeholder for a page that is gone"))
            .crannyCard(cells: columns)
            // Light never sits behind text without a card or a scrim (DESIGN.md §5): Flat style draws no card.
            .background { if theme.widgetStyle != .cards { theme.palette.scrim } }
    }
}

#Preview("Open panel · Home") {
    let (model, registry) = previewScene(.open)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: model.layout.canvasSize.height)
        .background(Color(white: 0.25))
}
