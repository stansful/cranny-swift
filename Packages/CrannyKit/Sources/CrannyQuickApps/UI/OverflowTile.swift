// CrannyQuickApps/UI/OverflowTile.swift — "+N": more tiles than cells. The Nook never scrolls (DESIGN.md §6.3),
// so the last cell lists the rest in a menu (with their icons); widening the widget shows them as tiles.
//
// The shortcuts it holds still show their run state here (DESIGN.md §7.3): the ring while one runs, the check
// after a success, the `danger` badge after a failure (`ShortcutRunState.combined`). The notch flashes their
// results too, because their own tiles are not on screen (`QuickAppsModel.isOnScreenAsTile`).
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
    /// Where the menu drops down (the grid also opens it from the keyboard).
    let anchor: MenuAnchor

    var body: some View {
        let p = theme.palette
        let more = String(localized: "\(count) more", bundle: .module, comment: "Quick Apps: the overflow tile (number of tiles that do not fit)")
        let state = ShortcutRunState.combined(shortcutStates)
        let interval = RunningRing.frameInterval(model.environment.effectBudget(isOpen: true, isOnScreen: true,
                                                                                reduceMotion: theme.reduceMotion))
        Button { Self.showMenu(tiles: tiles, model: model, redacted: redacted, anchor: anchor) } label: {
            TileContent(metrics: metrics, label: model.showsLabels ? more : nil, isRunning: false) {
                RoundedRectangle(cornerRadius: metrics.squircleRadius, style: .continuous)
                    .fill(p.control)
                    .frame(width: metrics.body, height: metrics.body)
                    .overlay {
                        RunStateGlyph(state: state, metrics: metrics, frameInterval: interval) {
                            Text(verbatim: "+\(count)")
                                .crannyFont(.headline)
                                .monospacedDigit()
                                .foregroundStyle(p.label)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(width: metrics.icon, height: metrics.icon)
                    .shortcutFailureBadge(state, metrics: metrics)
            }
        }
        .buttonStyle(TileButtonStyle(metrics: metrics))
        .focusable(false)                       // the grid makes the tile itself focusable (arrows)
        .disabled(!interactive)
        .menuAnchor(anchor, enabled: interactive)
        .help(helpText(more: more, state: state))
        .accessibilityLabel(Text(verbatim: more))
        .accessibilityValue(Text(verbatim: accessibilityValue(state)))
        // Menu rows show cached icons only: render their size off the main actor while the tile is on screen.
        .task(id: tiles.map(\.id)) {
            for case .app(let app) in tiles { _ = await model.catalog.icon(at: app.url, pixelSize: AppIconView.menuPixels) }
        }
    }

    private var shortcutStates: [ShortcutRunState] {
        tiles.compactMap { tile in if case .shortcut(let entry) = tile { model.runs.state(of: entry.id) } else { nil } }
    }

    private func helpText(more: String, state: ShortcutRunState) -> String {
        if case .failed(let error) = state { return "\(more)\n\(error.localizedDescription)" }
        return more
    }

    private func accessibilityValue(_ state: ShortcutRunState) -> String {
        switch state {
        case .running: String(localized: "Running", bundle: .module, comment: "Quick Apps: VoiceOver value of an open app / a running shortcut")
        case .succeeded: String(localized: "Finished", bundle: .module, comment: "Quick Apps: VoiceOver value of a shortcut that just ran")
        case .failed(let error): error.localizedDescription
        case .idle: ""
        }
    }

    /// Drops the menu of `tiles` down under the "+N" tile (click, ↩ / Space on the focused tile, VoiceOver).
    /// A running shortcut's row stops it; a failed one says why in its tooltip.
    static func showMenu(tiles: [LauncherTile], model: QuickAppsModel, redacted: Bool, anchor: MenuAnchor?) {
        let entries = tiles.map { tile -> MenuEntry in
            switch tile {
            case .app(let app):
                return MenuEntry(app.name, image: AppIconView.menuImage(for: app, catalog: model.catalog)) { model.activate(tile) }
            case .shortcut(let entry):
                let name = redacted ? QuickAppsModel.neutralShortcutName : entry.displayName
                let image = ShortcutMenuImage.image(for: entry, redacted: redacted)
                switch model.runs.state(of: entry.id) {
                case .running:
                    let title = String(localized: "\(name) — click to stop", bundle: .module, comment: "Quick Apps: a running shortcut's tooltip and \"+N\" menu row (shortcut name)")
                    return MenuEntry(title, image: image) { model.activate(tile) }
                case .failed(let error):
                    return MenuEntry(name, image: image, toolTip: error.localizedDescription) { model.activate(tile) }
                case .idle, .succeeded:
                    return MenuEntry(name, image: image) { model.activate(tile) }
                }
            }
        }
        PopUpMenu.show(entries, anchor: anchor)
    }
}

#Preview("Overflow tile") {
    let model = QuickAppsPreview.model(states: [QuickAppsPreview.sampleShortcuts[2].id: .failed(.shortcutFailed)])
    OverflowTile(tiles: model.tiles, count: model.tiles.count, model: model,
                 metrics: TileMetrics(tile: 56, showsLabels: false), interactive: true, redacted: false, anchor: MenuAnchor())
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
