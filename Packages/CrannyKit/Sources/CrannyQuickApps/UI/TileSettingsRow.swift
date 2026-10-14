// CrannyQuickApps/UI/TileSettingsRow.swift — one row of Settings ▸ Shortcuts' tile list: icon or squircle, name,
// what it is (or that it is missing), "Customise…" for shortcuts, remove; Move Up/Down in its menu and for VoiceOver.
import CrannyCore
import SwiftUI

struct TileSettingsRow: View {
    enum Row: Identifiable {
        case app(bundleID: String, app: ResolvedApp?)
        case shortcut(ShortcutEntry, isMissing: Bool)

        var id: TileID {
            switch self {
            case .app(let bundleID, _): .app(bundleID)
            case .shortcut(let entry, _): .shortcut(entry.id)
            }
        }
    }

    let row: Row
    let model: QuickAppsModel
    let isFirst: Bool
    let isLast: Bool
    @State private var isCustomizing = false

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title).lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(isMissing ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if case .shortcut = row {
                Button { isCustomizing = true } label: {
                    Text("Customise…", bundle: .module, comment: "Settings ▸ Shortcuts: opens a shortcut's symbol and colour")
                }
                .buttonStyle(.link)
                .popover(isPresented: $isCustomizing, arrowEdge: .trailing) { appearanceEditor }
            }
            Button { model.remove(row.id) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action"))
            .accessibilityLabel(Text("Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action"))
        }
        .padding(.vertical, 2)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityActions { menu }
    }

    // MARK: Parts

    @ViewBuilder private var icon: some View {
        switch row {
        case .app(_, let app?):
            AppIconView(url: app.url, catalog: model.catalog, size: 24)
        case .app(_, nil):
            Image(systemName: "app.dashed")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .shortcut(let entry, _):
            Button { isCustomizing = true } label: { ShortcutGlyph(entry: entry, size: 24) }
                .buttonStyle(.plain)
                .help(String(localized: "Symbol and colour", bundle: .module, comment: "Settings ▸ Shortcuts: tooltip of a shortcut's squircle"))
        }
    }

    @ViewBuilder private var appearanceEditor: some View {
        if case .shortcut(let entry, _) = row {
            ShortcutAppearanceEditor(model: model, id: entry.id)
        }
    }

    @ViewBuilder private var menu: some View {
        Button { model.move(row.id, by: -1) } label: { Text("Move Up", bundle: .module, comment: "Settings ▸ Shortcuts: reorder a tile") }
            .disabled(isFirst)
        Button { model.move(row.id, by: 1) } label: { Text("Move Down", bundle: .module, comment: "Settings ▸ Shortcuts: reorder a tile") }
            .disabled(isLast)
        if case .app(_, let app?) = row {
            Button { model.launcher.reveal(app.url) } label: {
                Text("Show in Finder", bundle: .module, comment: "Quick Apps: tile menu / VoiceOver action")
            }
        }
        Button(role: .destructive) { model.remove(row.id) } label: {
            Text("Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action")
        }
    }

    // MARK: Text

    private var isMissing: Bool {
        switch row {
        case .app(_, let app): app == nil && model.catalog.hasResolved
        case .shortcut(_, let isMissing): isMissing
        }
    }

    private var title: String {
        switch row {
        case .app(let bundleID, let app): app?.name ?? bundleID
        case .shortcut(let entry, _): entry.displayName
        }
    }

    private var subtitle: String {
        switch row {
        case .app:
            isMissing
                ? String(localized: "Not installed", bundle: .module, comment: "Settings ▸ Shortcuts: an app in the list that is not on this Mac")
                : String(localized: "App", bundle: .module, comment: "Quick Apps: an app (⌘K result kind, Settings row subtitle)")
        case .shortcut:
            isMissing
                ? String(localized: "Not found in Shortcuts", bundle: .module, comment: "Settings ▸ Shortcuts: a shortcut deleted in Shortcuts.app")
                : String(localized: "Shortcut", bundle: .module, comment: "Quick Apps: a Shortcuts.app shortcut (⌘K result kind, Settings row subtitle, neutral tile name in Demo mode)")
        }
    }
}

#Preview("Tile rows") {
    let model = QuickAppsPreview.model()
    Form {
        TileSettingsRow(row: .app(bundleID: "com.apple.Safari", app: PreviewAppResolver.app(for: "com.apple.Safari")),
                        model: model, isFirst: true, isLast: false)
        TileSettingsRow(row: .app(bundleID: "com.example.gone", app: nil), model: model, isFirst: false, isLast: false)
        TileSettingsRow(row: .shortcut(QuickAppsPreview.sampleShortcuts[0], isMissing: false), model: model, isFirst: false, isLast: false)
        TileSettingsRow(row: .shortcut(QuickAppsPreview.sampleShortcuts[1], isMissing: true), model: model, isFirst: false, isLast: true)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 320)
}
