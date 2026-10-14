// CrannyTray/Store/TrayStore+Actions.swift — what tiles, chips, the context menu and keys do (DESIGN.md §8.1
// "Interaction", §16 keyboard map): selection, open, reveal, Quick Look, copy, AirDrop, Share. Sharing goes through
// the shell (`NotchControl.presentAirDrop/presentSharePicker`, R3 §7); the rest through `TraySystem`.
import CrannyCore
import Foundation

extension TrayStore {
    /// The items an action applies to: the selection if `id` is part of it (or no `id`), else just `id`.
    func targets(for id: UUID?) -> [TrayItem] {
        if let id, !selection.contains(id) { return items.filter { $0.id == id } }
        return selectedItems
    }

    /// Resolved URLs of `items` (missing files are skipped).
    func urls(of targets: [TrayItem]) -> [URL] { targets.compactMap { urls[$0.id] } }

    // MARK: Selection

    func click(_ id: UUID, modifiers: TraySelection.Modifiers) {
        selection.click(id, modifiers: modifiers, order: order)
        failures[id] = nil
    }
    func selectAll() { selection.selectAll(order) }
    func moveSelection(forward: Bool, extend: Bool) { selection.move(forward: forward, extend: extend, order: order) }
    func clearSelection() { selection.clear() }

    /// Leaving the Tray page: "new" dots go, the selection stays.
    func pageDidDisappear() { freshItems = [] }

    // MARK: Files

    /// Double-click / ↩: opens in the default app.
    func open(_ id: UUID? = nil) { system.open(urls(of: targets(for: id))) }

    func reveal(_ id: UUID? = nil) { system.reveal(urls(of: targets(for: id))) }

    /// Space: Quick Look on the selection (or `id`), starting at the focused tile.
    func toggleQuickLook(_ id: UUID? = nil) {
        if system.isQuickLookVisible { return system.closeQuickLook() }
        let targets = targets(for: id)
        let list = urls(of: targets.isEmpty ? items : targets)
        let focus = id ?? selection.cursor
        let start = focus.flatMap { f in (targets.isEmpty ? items : targets).firstIndex { $0.id == f } } ?? 0
        system.quickLook(list, at: start)
    }

    /// ⌘C: the files themselves (paste them in Finder or Mail).
    func copyFiles(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        system.copy(files: list)
    }

    /// "Copy Path" (context menu) and the Copy paths chip; confirmed in the band (`NotchControl.flash`).
    func copyPaths(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        system.copy(text: list.map(\.path).joined(separator: "\n"))
        notch.flash(symbol: "link", label: list.count == 1
            ? String(localized: "Path copied", bundle: .module, comment: "Notch flash after Copy paths (one file); at most 12 characters")
            : String(localized: "Paths copied", bundle: .module, comment: "Notch flash after Copy paths (several files); at most 12 characters"))
    }

    /// ⌘⌫ / ✕ / "Remove": removes the selection (or `id`).
    func removeTargets(_ id: UUID? = nil) { remove(Set(targets(for: id).map(\.id))) }

    // MARK: Sharing (the shell anchors the sheets and gives focus back, R3 §7)

    func airDrop(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        let notch = notch
        Task { _ = await notch.presentAirDrop(list) }
    }

    /// Files dropped on an AirDrop zone go straight to the AirDrop sheet; they are not kept.
    func airDrop(dropped urls: [URL]) async -> Bool {
        guard !urls.isEmpty else { return false }
        return await notch.presentAirDrop(urls)
    }

    func share(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        notch.presentSharePicker(list)
    }

    // MARK: Drag out

    /// A drag-out session started: keep Cranny open while the pointer travels (DESIGN.md §4.6 "dragging").
    func dragOutBegan() { notch.setHoldOpen(true, reason: Self.dragOutHold) }

    /// The receiver moved or trashed the files: those items leave the Tray.
    func dragOutEnded(_ ids: [UUID], movedOrDeleted: Bool) {
        notch.setHoldOpen(false, reason: Self.dragOutHold)
        guard movedOrDeleted else { return }
        Task { await removeIfGone(ids) }
    }

    static let dragOutHold = "tray.dragOut"
}
