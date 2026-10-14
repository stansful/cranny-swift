// CrannyQuickApps/UI/OverflowTile.swift — "+N": more tiles than cells. The Nook never scrolls (DESIGN.md §6.3),
// so the last cell lists the rest in a menu (with their icons); widening the widget shows them as tiles.
import AppKit
import CrannyCore
import SwiftUI

struct OverflowTile: View {
    @Environment(\.cranny) private var theme
    let tiles: [LauncherTile]
    let count: Int
    let model: QuickAppsModel
    let metrics: TileMetrics
    let interactive: Bool
    let redacted: Bool

    var body: some View {
        let p = theme.palette
        let more = String(localized: "\(count) more", bundle: .module, comment: "Quick Apps: the overflow tile (number of tiles that do not fit)")
        Button { PopUpMenu.show(entries) } label: {
            TileContent(metrics: metrics, label: model.showsLabels ? more : nil, isRunning: false) {
                RoundedRectangle(cornerRadius: metrics.squircleRadius, style: .continuous)
                    .fill(p.control)
                    .frame(width: metrics.body, height: metrics.body)
                    .overlay {
                        Text(verbatim: "+\(count)")
                            .crannyFont(.headline)
                            .monospacedDigit()
                            .foregroundStyle(p.label)
                            .minimumScaleFactor(0.6)
                    }
            }
        }
        .buttonStyle(TileButtonStyle(metrics: metrics))
        .focusable(false)
        .disabled(!interactive)
        .help(more)
        .accessibilityLabel(Text(verbatim: more))
    }

    private var entries: [MenuEntry] {
        tiles.map { tile in
            switch tile {
            case .app(let app):
                MenuEntry(app.name, image: AppIconView.menuImage(for: app, catalog: model.catalog)) { model.activate(tile) }
            case .shortcut(let entry):
                MenuEntry(redacted ? String(localized: "Shortcut", bundle: .module, comment: "Quick Apps: a Shortcuts.app shortcut (⌘K result kind, Settings row subtitle, neutral tile name in Demo mode)") : entry.displayName,
                          image: ShortcutGlyph.menuImage(for: entry)) { model.activate(tile) }
            }
        }
    }
}

#Preview("Overflow tile") {
    let model = QuickAppsPreview.model()
    OverflowTile(tiles: model.tiles, count: model.tiles.count, model: model,
                 metrics: TileMetrics(tile: 56, showsLabels: false), interactive: true, redacted: false)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
