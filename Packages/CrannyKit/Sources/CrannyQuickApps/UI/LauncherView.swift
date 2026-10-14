// CrannyQuickApps/UI/LauncherView.swift — the launcher widget's content (DESIGN.md §7.3, §6.8).
//
// Tiles are grid cells, so the grid is laid out on the WHOLE card and pulled back over the card padding the
// shell applies (`.padding(-cardPadding)`); the card still clips and fills. States: content · empty (one line +
// "Add App…") · loading (nothing for the first lookup, ≤ 300 ms) · drop target armed (an app dragged over it).
import CrannyCore
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    static let dropZone: DropZoneID = "quickapps.addApps"

    @Environment(\.cranny) private var theme
    @Environment(\.notchZones) private var zones
    let model: QuickAppsModel
    let context: WidgetContext

    var body: some View {
        let interactive = !context.isPreview && !context.isEditingLayout
        let tiles = model.tiles
        let grid = theme.grid
        let padding = grid.density.cardPadding
        let card = CGSize(width: context.contentSize.width + 2 * padding, height: context.contentSize.height + 2 * padding)
        let layout = LauncherLayout(columns: context.cells, rows: context.rows)
        ZStack {
            if !model.isReady {
                DelayedLoading()
            } else if tiles.isEmpty && !model.isEditing && context.cells > 1 {
                WidgetStateView(.empty, symbol: "app.dashed",
                                message: String(localized: "Drag apps here", bundle: .module, comment: "Quick Apps widget: empty state"),
                                actionTitle: interactive ? String(localized: "Add App…", bundle: .module, comment: "Quick Apps: add an app with the open panel") : nil,
                                action: interactive ? chooseApps : nil)
            } else {
                LauncherGrid(model: model, tiles: tiles, layout: layout,
                             metrics: LauncherMetrics(cardSize: card, columns: layout.columns, rows: layout.rows, cell: grid.cell),
                             interactive: interactive, redacted: context.redactsPersonalData)
                    .frame(width: card.width, height: card.height, alignment: .topLeading)
                    .padding(-padding)
            }
            if isDropTarget {
                DropZone(symbol: "plus",
                         title: context.cells > 1 ? String(localized: "Add to Quick Apps", bundle: .module, comment: "Quick Apps: the + tile (tooltip, VoiceOver)") : "",
                         targeted: true)
                    .transition(.opacity)
            }
        }
        .frame(width: context.contentSize.width, height: context.contentSize.height)
        .contentShape(Rectangle())
        .onTapGesture { if model.isEditing { withAnimation(theme.animation(.commit)) { model.isEditing = false } } }
        .contextMenu { if interactive { LauncherEditMenuItems(model: model) } }
        .crannyDropZone(Self.dropZone, accepts: [.application]) { payload in await model.acceptDrop(payload) }
        .background { if interactive { LauncherKeyboardShortcuts(model: model, tiles: tiles) } }
        .animation(theme.animation(.commit), value: isDropTarget)
        .animation(theme.animation(.listReorder), value: model.isEditing)
        .animation(theme.animation(.listReorder), value: tiles.map(\.id))
        .onChange(of: isDropTarget) { _, armed in if armed { model.haptics.play(.alignment) } }
    }

    private var chooseApps: @MainActor () -> Void { { [model] in model.chooseApps() } }

    private var isDropTarget: Bool { zones?.armedDropZone == Self.dropZone }
}

/// DESIGN.md §6.8 loading: nothing for the first 300 ms, then a quiet ring (the first app lookup is ≈ 10 ms).
private struct DelayedLoading: View {
    @State private var isLate = false
    var body: some View {
        ZStack {
            if isLate {
                WidgetStateView(.loading, symbol: "app.dashed",
                                message: String(localized: "Loading…", bundle: .module, comment: "Quick Apps: loading (widget while apps are looked up, shortcut submenu while the list is read)"))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            isLate = true
        }
    }
}

#Preview("Launcher · 2 cells") {
    QuickAppsPreview.widget(cells: 2)
}

#Preview("Launcher · 4 cells, labels") {
    QuickAppsPreview.widget(cells: 4, showsLabels: true)
}

#Preview("Launcher · 1 cell, editing") {
    QuickAppsPreview.widget(cells: 1, editing: true)
}

#Preview("Launcher · empty") {
    QuickAppsPreview.widget(cells: 2, apps: [], shortcuts: [])
}
