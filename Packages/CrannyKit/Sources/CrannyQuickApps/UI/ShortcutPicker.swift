// CrannyQuickApps/UI/ShortcutPicker.swift — Settings ▸ Shortcuts ▸ "Add Shortcut…": every Shortcuts.app shortcut
// with a checkbox, searchable; states for reading, failure (Try Again) and an empty Shortcuts app (Open Shortcuts).
import CrannyCore
import SwiftUI

struct ShortcutPicker: View {
    let model: QuickAppsModel
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(text: $query) {
                    Text("Search shortcuts", bundle: .module, comment: "Settings ▸ Shortcuts picker: search field placeholder")
                }
                .textFieldStyle(.roundedBorder)
                Button { Task { await model.shortcutsCatalog.refresh() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Reload from Shortcuts", bundle: .module, comment: "Settings ▸ Shortcuts picker: reload button"))
                .accessibilityLabel(Text("Reload from Shortcuts", bundle: .module, comment: "Settings ▸ Shortcuts picker: reload button"))
                .disabled(model.shortcutsCatalog.state == .loading)
            }
            .padding(10)
            Divider()
            content
                .frame(width: 320, height: 300)
        }
        .task { await model.shortcutsCatalog.refresh(maximumAge: 30) }
    }

    @ViewBuilder private var content: some View {
        let catalog = model.shortcutsCatalog
        if !catalog.shortcuts.isEmpty {
            let matches = filtered(catalog.shortcuts)
            if matches.isEmpty {
                message(Text("No shortcuts match “\(query)”", bundle: .module, comment: "Settings ▸ Shortcuts picker: no search results (query)"))
            } else {
                List(matches) { info in
                    Toggle(isOn: binding(for: info)) {
                        HStack(spacing: 8) {
                            ShortcutGlyph(entry: entry(for: info), size: 20)
                            Text(verbatim: entry(for: info).displayName).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.plain)
            }
        } else {
            switch catalog.state {
            case .idle, .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                VStack(spacing: 10) {
                    Text(verbatim: error.localizedDescription).foregroundStyle(.secondary)
                    Button { Task { await catalog.refresh() } } label: {
                        Text("Try Again", bundle: .module, comment: "Settings ▸ Shortcuts picker: retry reading the list")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                VStack(spacing: 10) {
                    Text("You have no shortcuts yet.", bundle: .module, comment: "Settings ▸ Shortcuts picker: Shortcuts.app has no shortcuts")
                        .foregroundStyle(.secondary)
                    Button { model.launcher.openShortcutsApp() } label: {
                        Text("Open Shortcuts", bundle: .module, comment: "Quick Apps: opens Shortcuts.app")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func message(_ text: Text) -> some View {
        text.foregroundStyle(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func filtered(_ list: [ShortcutInfo]) -> [ShortcutInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter { CommandMatcher.score([$0.name], query: q) != nil }
    }

    /// The stored entry (with its symbol and colour) when the shortcut is already on the launcher.
    private func entry(for info: ShortcutInfo) -> ShortcutEntry {
        model.shortcutEntries.first { $0.id == info.id } ?? ShortcutEntry(id: info.id, name: info.name)
    }

    private func binding(for info: ShortcutInfo) -> Binding<Bool> {
        Binding(get: { model.isAdded(shortcut: info.id) },
                set: { isOn in if isOn { model.add(shortcut: info) } else { model.remove(.shortcut(info.id)) } })
    }
}

#Preview("Shortcut picker") {
    let model = QuickAppsPreview.model()
    ShortcutPicker(model: model)
        .task { await model.shortcutsCatalog.refresh() }
}
