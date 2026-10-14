// CrannyTray/UI/TrayPage.swift — the Tray page (DESIGN.md §8.1, full width): a files card of (width − 2) cells with
// the tile row and the chip row, and a 2-cell AirDrop card. The files card is also a drop zone (keep), the AirDrop
// card sends what is dropped on it. Laid out at its final size like every Nook page (no reflow during the morph).
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Drop zone ids of the Tray's own surfaces (distinct per surface, so appearing and disappearing never clash).
enum TrayDropZones {
    static let page: DropZoneID = "tray.page.keep"
    static let pageAirDrop: DropZoneID = "tray.page.airdrop"
    static let shelf: DropZoneID = "tray.shelf.keep"
    static let catchAirDrop: DropZoneID = "tray.catch.airdrop"
    static func catchPipeline(_ id: String) -> DropZoneID { DropZoneID("tray.catch.\(id)") }
}

struct TrayPage: View {
    @Environment(\.cranny) private var theme
    let store: TrayStore
    let context: WidgetContext

    var body: some View {
        if let types = TrayQA.catchTypes {
            CatchView(store: store, types: types)          // Debug QA only (`--qa-tray-catch`)
        } else {
            page
        }
    }

    @ViewBuilder private var page: some View {
        let showsAirDrop = store.settings[TraySettings.showsAirDropZone] && context.cells >= 6
        let airDropCells = showsAirDrop ? 2 : 0
        HStack(spacing: theme.grid.gutter) {
            TrayFilesCard(store: store, isInteractive: !context.isPreview)
                .crannyCard(cells: max(context.cells - airDropCells, 1))
            if showsAirDrop {
                AirDropZoneView(store: store, cells: airDropCells, zone: TrayDropZones.pageAirDrop, isInteractive: !context.isPreview)
                    .crannyCard(cells: airDropCells)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task { await store.refreshLocations() }
        .onDisappear { store.pageDidDisappear() }
    }
}

/// The files card's content: tiles + chips, or the empty state.
struct TrayFilesCard: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchZones) private var zones
    let store: TrayStore
    var isInteractive = true

    var body: some View {
        let armed = zones?.armedDropZone == TrayDropZones.page
        Group {
            if store.items.isEmpty && store.jobs.isEmpty {
                WidgetStateView(.empty, symbol: "tray.and.arrow.down.fill",
                                message: String(localized: "Drop files on the notch to keep them here", bundle: .module,
                                                comment: "Tray page: empty state"))
            } else {
                VStack(alignment: .leading, spacing: Space.m) {
                    TrayTileRow(store: store, isInteractive: isInteractive)
                    PipelineChips(store: store)
                        .allowsHitTesting(isInteractive)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if armed { TrayArmedOverlay() } }
        .crannyDropZone(TrayDropZones.page, accepts: [.item]) { payload in await store.keep(payload.fileURLs, opensTray: false) }
        .onChange(of: armed) { _, isArmed in if isArmed { store.haptics.play(.alignment) } }
        .animation(theme.animation(.commit), value: armed)
    }
}

/// The armed look of a surface that is not a `DropZone` (accent at 15 %, solid accent stroke; DESIGN.md §8.3).
struct TrayArmedOverlay: View {
    @Environment(\.cranny) private var theme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.grid.innerRadius, style: .continuous)
        shape.fill(theme.accentColor.opacity(0.15))
            .overlay(shape.strokeBorder(theme.accentColor, lineWidth: StrokeWidth.emphasis))
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

#Preview("Tray page · items") {
    let store = TrayPreview.store(items: 6, selected: 2)
    TrayPage(store: store, context: TrayPreview.pageContext(cells: 10))
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Tray page · empty") {
    let store = TrayPreview.store(items: 0)
    TrayPage(store: store, context: TrayPreview.pageContext(cells: 10))
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
