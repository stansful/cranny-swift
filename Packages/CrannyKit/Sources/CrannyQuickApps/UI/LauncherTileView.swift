// CrannyQuickApps/UI/LauncherTileView.swift — one app or shortcut tile with its behaviour: click / ↩ launches
// or runs (a running shortcut stops), right-click menu, tooltip, hold-⌘ hint (⌥1–⌥9), VoiceOver label, value,
// hint and actions; in edit mode a remove badge and drag to reorder (DESIGN.md §7.3, §16).
import CrannyCore
import SwiftUI

struct LauncherTileView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var notchContext
    let tile: LauncherTile
    /// Position among the visible tiles (⌥ number, VoiceOver moves).
    let index: Int
    let count: Int
    let model: QuickAppsModel
    let metrics: TileMetrics
    let interactive: Bool
    let redacted: Bool
    let isFocused: Bool
    var onDrag: (DragGesture.Value) -> Void = { _ in }
    var onDragEnd: () -> Void = {}

    var body: some View {
        let editing = model.isEditing && interactive
        Group {
            if editing {
                content
                    .frame(width: metrics.tile, height: metrics.tile)
                    .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .onTapGesture {}                        // a click on a tile does not end edit mode (the card's does)
                    .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(LauncherGrid.space))
                        .onChanged(onDrag)
                        .onEnded { _ in onDragEnd() })
                    .overlay(alignment: .topLeading) {
                        RemoveBadge(size: metrics.removeBadge) { withAnimation(theme.animation(.listReorder)) { model.remove(tile.id) } }
                            .offset(x: -Space.xxs, y: -Space.xxs)
                            .transition(.opacity)
                    }
            } else {
                Button { model.activate(tile) } label: { content }
                    .buttonStyle(TileButtonStyle(metrics: metrics))
                    .focusable(false)                       // the grid makes the tile itself focusable (arrows)
                    .disabled(!interactive)
            }
        }
        .overlay(alignment: .bottom) {
            // Hold-⌘ hint, a tag on the icon's lower edge where the running dot sits (DESIGN.md §6.5).
            if showsHint {
                KeyCap("⌥\(index + 1)")
                    .background(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).fill(theme.palette.surface))
                    .transition(.opacity)
            }
        }
        .animation(theme.animation(.hover), value: notchContext.showsCommandHints)
        .crannyFocusRing(isFocused, radius: Radius.tile)
        .help(helpText)
        .contextMenu { if interactive { TileMenu(tile: tile, model: model) } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(verbatim: displayName))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityHint(index < 9 ? Text("Option-\(index + 1)", bundle: .module, comment: "Quick Apps: VoiceOver hint, the tile's keyboard shortcut ⌥1–⌥9") : Text(verbatim: ""))
        .accessibilityAction { if interactive && !model.isEditing { model.activate(tile) } }
        .accessibilityActions { if interactive { accessibilityActions } }
    }

    private var showsHint: Bool { interactive && notchContext.showsCommandHints && index < 9 }

    // MARK: Face

    @ViewBuilder private var content: some View {
        let label = model.showsLabels ? displayName : nil
        switch tile {
        case .app(let app):
            TileContent(metrics: metrics, label: label, isRunning: model.running.isRunning(app.bundleID) && !showsHint) {
                AppIconView(url: app.url, catalog: model.catalog, size: metrics.icon)
            }
        case .shortcut(let entry):
            TileContent(metrics: metrics, label: label, isRunning: false) {
                ShortcutTileFace(entry: entry, state: model.runs.state(of: entry.id), metrics: metrics, redacted: redacted,
                                 frameInterval: RunningRing.frameInterval(
                                    model.environment.effectBudget(isOpen: true, isOnScreen: true, reduceMotion: theme.reduceMotion)))
            }
        }
    }

    private var displayName: String {
        if redacted, case .shortcut = tile {
            return String(localized: "Shortcut", bundle: .module, comment: "Quick Apps: a Shortcuts.app shortcut (⌘K result kind, Settings row subtitle, neutral tile name in Demo mode)")
        }
        return tile.name
    }

    private var runState: ShortcutRunState {
        if case .shortcut(let entry) = tile { model.runs.state(of: entry.id) } else { .idle }
    }

    private var helpText: String {
        switch runState {
        case .running:
            String(localized: "\(displayName) — click to stop", bundle: .module, comment: "Quick Apps: a running shortcut's tooltip and \"+N\" menu row (shortcut name)")
        case .failed(let error):
            "\(displayName)\n\(error.localizedDescription)"
        case .idle, .succeeded:
            displayName
        }
    }

    private var accessibilityValue: String {
        switch tile {
        case .app(let app):
            model.running.isRunning(app.bundleID)
                ? String(localized: "Running", bundle: .module, comment: "Quick Apps: VoiceOver value of an open app / a running shortcut") : ""
        case .shortcut:
            switch runState {
            case .running: String(localized: "Running", bundle: .module, comment: "Quick Apps: VoiceOver value of an open app / a running shortcut")
            case .succeeded: String(localized: "Finished", bundle: .module, comment: "Quick Apps: VoiceOver value of a shortcut that just ran")
            case .failed(let error): error.localizedDescription
            case .idle: ""
            }
        }
    }

    @ViewBuilder private var accessibilityActions: some View {
        if case .app(let app) = tile {
            Button { model.launcher.reveal(app.url) } label: {
                Text("Show in Finder", bundle: .module, comment: "Quick Apps: tile menu / VoiceOver action")
            }
        }
        if index > 0 {
            Button { model.move(tile.id, toVisibleIndex: index - 1) } label: {
                Text("Move earlier", bundle: .module, comment: "Quick Apps: VoiceOver action, reorder tiles")
            }
        }
        if index < count - 1 {
            Button { model.move(tile.id, toVisibleIndex: index + 1) } label: {
                Text("Move later", bundle: .module, comment: "Quick Apps: VoiceOver action, reorder tiles")
            }
        }
        Button { model.remove(tile.id) } label: {
            Text("Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action")
        }
    }
}

/// Right-click menu of a tile.
struct TileMenu: View {
    let tile: LauncherTile
    let model: QuickAppsModel

    var body: some View {
        switch tile {
        case .app(let app):
            Button { model.activate(tile) } label: { Text("Open", bundle: .module, comment: "Quick Apps: tile menu, open the app") }
            Button { model.launcher.reveal(app.url) } label: {
                Text("Show in Finder", bundle: .module, comment: "Quick Apps: tile menu / VoiceOver action")
            }
        case .shortcut(let entry):
            if model.runs.isRunning(entry.id) {
                Button { model.toggleRun(entry) } label: { Text("Stop", bundle: .module, comment: "Quick Apps: tile menu, stop a running shortcut") }
            } else {
                Button { model.toggleRun(entry) } label: { Text("Run", bundle: .module, comment: "Quick Apps: tile menu, run the shortcut") }
            }
        }
        Divider()
        Button { model.remove(tile.id) } label: {
            Text("Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action")
        }
        Divider()
        LauncherEditMenuItems(model: model)
    }
}

/// "Edit tiles"/"Done", "Add app…", "Quick Apps Settings…": shared by the tile and card menus.
struct LauncherEditMenuItems: View {
    let model: QuickAppsModel
    var body: some View {
        if model.isEditing {
            Button { model.isEditing = false } label: { Text("Done editing", bundle: .module, comment: "Quick Apps: menu item, leave edit mode") }
        } else {
            Button { model.isEditing = true } label: { Text("Edit tiles", bundle: .module, comment: "Quick Apps: menu item, enter edit mode (remove, reorder, add)") }
        }
        Button { model.chooseApps() } label: { Text("Add app…", bundle: .module, comment: "Quick Apps: add an app with the open panel") }
        Button { model.openSettings() } label: { Text("Quick Apps Settings…", bundle: .module, comment: "Quick Apps: opens Settings ▸ Shortcuts") }
    }
}

#Preview("Tiles") {
    let model = QuickAppsPreview.model()
    let metrics = TileMetrics(tile: 56, showsLabels: false)
    let tiles = model.tiles
    HStack(spacing: Space.m) {
        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
            LauncherTileView(tile: tile, index: index, count: tiles.count, model: model, metrics: metrics,
                             interactive: true, redacted: false, isFocused: index == 0)
        }
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
