// CrannyQuickApps/Model/QuickAppsModel+Editing.swift — adding, removing, reordering and styling tiles.
// Every change is a settings write, so Reset, Undo and the other display's panel follow automatically.
import AppKit
import CrannyCore
import Foundation
import UniformTypeIdentifiers

extension QuickAppsModel {
    // MARK: - Apps

    /// Adds the apps among `urls` (drops on the launcher or Settings, the open panel); returns how many were new.
    @discardableResult
    func addApps(at urls: [URL]) async -> Int {
        add(await catalog.apps(at: urls))
    }

    /// A file drop on the launcher (`.crannyDropZone(accepts: [.application])`): adds the apps among the files.
    /// Taken (true) when it held at least one app, new or not; other files are left for the shell's fallback.
    func acceptDrop(_ payload: DropPayload) async -> Bool {
        let apps = await catalog.apps(at: payload.fileURLs)
        add(apps)
        return !apps.isEmpty
    }

    @discardableResult
    func add(_ apps: [ResolvedApp]) -> Int {
        var entries = appEntries
        var added = 0
        for app in apps {
            catalog.insert(app)
            guard !entries.contains(where: { $0.bundleID == app.bundleID }) else { continue }
            entries.append(AppEntry(bundleID: app.bundleID))
            added += 1
        }
        if added > 0 { settings[QuickAppsSettings.apps] = entries }
        return added
    }

    /// "Add App…": the system open panel at /Applications (multiple selection). The panel stays open meanwhile.
    func chooseApps() {
        let hold = "quickapps.choosingApps"
        notch.setHoldOpen(true, reason: hold)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Add", bundle: .module, comment: "Quick Apps: add (open panel confirm button, name under the + tile)")
        panel.message = String(localized: "Choose apps to add to Quick Apps.", bundle: .module, comment: "Quick Apps: open panel message")
        NSApp.activate()
        panel.begin { [weak self] response in
            let urls = response == .OK ? panel.urls : []
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !urls.isEmpty { await self.addApps(at: urls) }
                self.notch.setHoldOpen(false, reason: hold)
            }
        }
    }

    // MARK: - Shortcuts

    func isAdded(shortcut id: String) -> Bool { shortcutEntries.contains { $0.id == id } }

    func add(shortcut info: ShortcutInfo) {
        guard !isAdded(shortcut: info.id) else { return }
        settings[QuickAppsSettings.shortcuts] = shortcutEntries + [ShortcutEntry(id: info.id, name: info.name)]
    }

    /// Symbol nil = first letter; tint nil = hashed hue.
    func setAppearance(of id: String, symbol: String?, tint: ShortcutTint?) {
        var entries = shortcutEntries
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].symbol = symbol
        entries[index].tint = tint
        settings[QuickAppsSettings.shortcuts] = entries
    }

    // MARK: - Any tile

    func remove(_ id: TileID) {
        switch id {
        case .app(let bundleID):
            settings[QuickAppsSettings.apps] = appEntries.filter { $0.bundleID != bundleID }
        case .shortcut(let shortcutID):
            runs.cancel(shortcutID)
            settings[QuickAppsSettings.shortcuts] = shortcutEntries.filter { $0.id != shortcutID }
        }
        let order = settings[QuickAppsSettings.order]
        if order.contains(id.rawValue) { settings[QuickAppsSettings.order] = order.filter { $0 != id.rawValue } }
    }

    /// Drag in edit mode, ⌥← / ⌥→, VoiceOver "Move earlier/later": `index` counts visible tiles only.
    func move(_ id: TileID, toVisibleIndex index: Int) {
        let next = LauncherOrder.move(id, toVisibleIndex: index, in: arrangement, isVisible: isVisible)
        writeOrder(next)
    }

    /// Settings list (which also lists apps that are not installed): moves by `offset` rows.
    func move(_ id: TileID, by offset: Int) {
        var all = arrangement
        guard let from = all.firstIndex(of: id) else { return }
        let to = min(max(from + offset, 0), all.count - 1)
        guard to != from else { return }
        all.remove(at: from)
        all.insert(id, at: to)
        writeOrder(all)
    }

    /// `List.onMove` in Settings (offsets in `arrangement`).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let all = arrangement
        let moving = source.sorted().filter(all.indices.contains).map { all[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        var rest = all.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        writeOrder(rest)
    }

    /// Persists a new order (a no-op when nothing moved, so the key stays at its default).
    private func writeOrder(_ ids: [TileID]) {
        guard ids != arrangement else { return }
        settings[QuickAppsSettings.order] = ids.map(\.rawValue)
    }
}
