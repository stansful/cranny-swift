// CrannyQuickApps/UI/ShortcutsSettingsPane.swift — Settings ▸ Shortcuts (DESIGN.md §11.1, §11.3): the launcher's
// tiles in their order (apps and shortcuts together, so the list reads like the widget), adding apps (open panel
// or a drop from Finder or the Dock) and shortcuts (a searchable picker), each shortcut's symbol and colour, and
// tile names. A Settings window follows the system appearance: system controls and colours only.
import CrannyCore
import SwiftUI

struct ShortcutsSettingsPane: View {
    let model: QuickAppsModel
    @State private var isPickingShortcuts = false
    @State private var isDropTargeted = false

    var body: some View {
        Form {
            Section {
                let rows = self.rows
                if rows.isEmpty {
                    Text("No tiles yet. Add an app or a shortcut.", bundle: .module, comment: "Settings ▸ Shortcuts: empty tile list")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    TileSettingsRow(row: row, model: model, isFirst: index == 0, isLast: index == rows.count - 1)
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                HStack(spacing: 12) {
                    Button { model.chooseApps() } label: {
                        Text("Add App…", bundle: .module, comment: "Quick Apps: add an app with the open panel")
                    }
                    Button { isPickingShortcuts = true } label: {
                        Text("Add Shortcut…", bundle: .module, comment: "Settings ▸ Shortcuts: opens the shortcut picker")
                    }
                    .popover(isPresented: $isPickingShortcuts, arrowEdge: .bottom) { ShortcutPicker(model: model) }
                }
            } header: {
                Text("Quick Apps", bundle: .module, comment: "Quick Apps: widget name (widget library, VoiceOver container)")
            } footer: {
                Text("Drag apps from Finder or the Dock onto this list. Apps that aren’t installed stay here but are hidden from Cranny.",
                     bundle: .module, comment: "Settings ▸ Shortcuts: footnote under the tile list")
                    .foregroundStyle(.secondary)
            }

            Section {
                DefaultAwareToggle(settings: model.settings, key: QuickAppsSettings.showsLabels) {
                    Text("Show names under tiles", bundle: .module, comment: "Quick Apps: option toggle (widget options, Settings ▸ Shortcuts)")
                }
            } header: {
                Text("Tiles", bundle: .module, comment: "Settings ▸ Shortcuts: section header")
            } footer: {
                Text("While Cranny is open, ⌥1–⌥9 open the first nine tiles. Click a running shortcut to stop it.",
                     bundle: .module, comment: "Settings ▸ Shortcuts: footnote about keys and stopping shortcuts")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.addApps(at: urls) }
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .task {
            async let shortcuts: Void = model.shortcutsCatalog.refresh(maximumAge: 30)
            async let apps: Void = model.catalog.refresh(model.appEntries.map(\.bundleID))
            _ = await (shortcuts, apps)
        }
    }

    private var rows: [TileSettingsRow.Row] {
        let shortcuts = Dictionary(model.shortcutEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return model.arrangement.compactMap { id in
            switch id {
            case .app(let bundleID):
                .app(bundleID: bundleID, app: model.catalog.app(bundleID))
            case .shortcut(let shortcutID):
                shortcuts[shortcutID].map { entry in
                    .shortcut(entry, isMissing: model.shortcutsCatalog.hasLoaded && model.shortcutsCatalog.info(for: entry.id) == nil)
                }
            }
        }
    }
}

/// A Bool setting row with the changed-from-default dot and "Reset to Default" (DESIGN.md §11.3).
struct DefaultAwareToggle<Label: View>: View {
    let settings: SettingsStore
    let key: SettingKey<Bool>
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: settings.binding(key)) { label() }
            .toggleStyle(.switch)
            .controlSize(.small)
            .crannySettingRow(settings, key)                  // Core's dot, "Reset to Default" and VoiceOver hint
    }
}

#Preview("Settings ▸ Shortcuts") {
    ShortcutsSettingsPane(model: QuickAppsPreview.model(apps: AppEntry.defaults.map(\.bundleID) + ["com.example.missing"]))
        .frame(width: 620, height: 560)
}
