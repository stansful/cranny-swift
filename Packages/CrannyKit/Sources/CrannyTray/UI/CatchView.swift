// CrannyTray/UI/CatchView.swift — the drag "catch" state (DESIGN.md §8.3), shown by CrannyNotchUI inside the open shape
// while a file drag is in progress (`TrayIntake.catchView(for:)`):
//   [ Keep in Tray (wide, ≥ 4 cells) ] [ AirDrop · 2 ] [ Compress · 2 ] [ Zip · 2 ] [ ✦ pipeline · 2 ]
// Keep and AirDrop always appear (AirDrop can be turned off in Settings), then up to 3 pinned pipelines that take the
// dragged types. The zone under the pointer arms (accent 15 %, solid stroke, 1.03, bounce, `.alignment` haptic).
// Dropping on an action runs it and keeps the result in the Tray.
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// How many cells each zone gets (pure, tested).
nonisolated enum CatchLayout {
    /// The minimum width of Keep in Tray (DESIGN.md §8.3).
    static let keepMinimum = 4
    static let zoneCells = 2

    /// Cells for (keep, airDrop?, pipelines…) in `total` cells: side zones are 2 cells; pipelines, then AirDrop, are
    /// dropped until Keep has at least 4 cells. Keep takes whatever is left.
    static func cells(total: Int, showsAirDrop: Bool, pipelines: Int) -> (keep: Int, airDrop: Int, pipelines: Int) {
        var airDrop = showsAirDrop ? zoneCells : 0
        var count = pipelines
        while total - airDrop - count * zoneCells < keepMinimum && count > 0 { count -= 1 }
        if total - airDrop - count * zoneCells < keepMinimum { airDrop = 0 }
        return (max(total - airDrop - count * zoneCells, 1), airDrop, count)
    }

    /// Whole cells that fit in `width` points.
    static func columns(width: CGFloat, grid: NookGrid) -> Int {
        max(Int((width + grid.gutter) / (grid.cell + grid.gutter)), 1)
    }
}

struct CatchView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchZones) private var zones
    let store: TrayStore
    let types: [UTType]

    var body: some View {
        GeometryReader { proxy in
            let grid = theme.grid
            let pipelines = BuiltinPipelines.catchZones(pinned: store.settings[TraySettings.pinnedPipelines],
                                                        userPipelines: store.settings[TraySettings.userPipelines], types: types)
            let layout = CatchLayout.cells(total: CatchLayout.columns(width: proxy.size.width, grid: grid),
                                           showsAirDrop: store.settings[TraySettings.showsAirDropZone],
                                           pipelines: pipelines.count)
            HStack(spacing: grid.gutter) {
                zone(.trayKeep, cells: layout.keep, symbol: "tray.and.arrow.down.fill",
                     title: String(localized: "Keep in Tray", bundle: .module, comment: "Drag catch state: drop zone that keeps the files"),
                     tint: nil, accepts: [.item]) { await store.keep($0.fileURLs) }
                if layout.airDrop > 0 {
                    zone(TrayDropZones.catchAirDrop, cells: layout.airDrop, symbol: "dot.radiowaves.up.forward", title: "AirDrop",
                         tint: theme.palette.info, accepts: [.item]) { await store.airDrop(dropped: $0.fileURLs) }
                }
                ForEach(pipelines.prefix(layout.pipelines)) { pipeline in
                    zone(TrayDropZones.catchPipeline(pipeline.id), cells: CatchLayout.zoneCells,
                         symbol: pipeline.isUserPipeline ? "wand.and.stars" : pipeline.symbol, title: store.title(of: pipeline),
                         tint: nil, accepts: pipeline.acceptedTypes) { await store.run(pipeline, dropped: $0.fileURLs) }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: theme.grid.height)
        .onChange(of: zones?.armedDropZone) { _, armed in
            if armed != nil { store.haptics.play(.alignment) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Drop zones", bundle: .module, comment: "Drag catch state: VoiceOver label of the row of drop zones"))
    }

    private func zone(_ id: DropZoneID, cells: Int, symbol: String, title: String, tint: Color?, accepts: [UTType],
                      perform: @escaping @MainActor (DropPayload) async -> Bool) -> some View {
        DropZone(symbol: symbol, title: title, targeted: zones?.armedDropZone == id, tint: tint)
            .crannyCard(cells: cells)
            .crannyDropZone(id, accepts: accepts, perform: perform)
            .accessibilityLabel(Text(verbatim: title))
    }
}

#Preview("Catch · images") {
    let store = TrayPreview.store(items: 2)
    CatchView(store: store, types: [.png])
        .frame(width: TrayPreview.pageContext(cells: 10).contentSize.width)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}

#Preview("Catch · narrow, any file") {
    let store = TrayPreview.store(items: 0)
    CatchView(store: store, types: [.pdf])
        .frame(width: TrayPreview.pageContext(cells: 7).contentSize.width)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
