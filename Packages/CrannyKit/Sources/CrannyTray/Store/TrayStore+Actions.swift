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
        followSelectionInQuickLook()
    }
    func selectAll() { selection.selectAll(order); followSelectionInQuickLook() }
    func moveSelection(forward: Bool, extend: Bool) {
        selection.move(forward: forward, extend: extend, order: order)
        followSelectionInQuickLook()
    }

    /// Like Finder: while Quick Look is up, it shows what is selected.
    private func followSelectionInQuickLook() {
        guard system.isQuickLookVisible, !selection.isEmpty else { return }
        let targets = selectedItems
        let start = selection.cursor.flatMap { c in targets.firstIndex { $0.id == c } } ?? 0
        system.quickLook(urls(of: targets), at: start)
    }
    func clearSelection() { selection.clear() }

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

    /// "Copy path" (context menu) and the Copy paths chip; confirmed in the band with the copy glyph and "Copied"
    /// (`NotchControl.flash`), and to VoiceOver with what was copied, since the glyph is not read out (DESIGN.md §16).
    func copyPaths(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        system.copy(text: list.map(\.path).joined(separator: "\n"))
        notch.flash(symbol: "doc.on.doc", label: Self.copiedLabel)
        system.announceFeedback(Self.pathsCopiedAnnouncement(count: list.count))
    }

    /// VoiceOver's confirmation of Copy paths: the flash's word alone («Готово») does not say what happened.
    static func pathsCopiedAnnouncement(count: Int) -> String {
        count == 1
            ? String(localized: "Path copied", bundle: .module, comment: "Tray: VoiceOver announcement after Copy paths (one file)")
            : String(localized: "Paths copied", bundle: .module, comment: "Tray: VoiceOver announcement after Copy paths (several files)")
    }

    /// ⌘⌫ / ✕ / "Remove": removes the selection (or `id`).
    func removeTargets(_ id: UUID? = nil) { remove(Set(targets(for: id).map(\.id))) }

    // MARK: Running pipelines (every path: hover ✕, Stop chip, ⌘., context menu, VoiceOver)

    /// The runs Stop applies to: those on the selected items (or `id`), else every run in progress (including runs on
    /// dropped files, whose tiles cannot be selected).
    func stoppableJobs(_ id: UUID? = nil) -> [TrayJob] {
        let running = jobs.filter { $0.failure == nil }
        let targetIDs = Set(targets(for: id).map(\.id))
        let mine = running.filter { $0.sourceIDs.contains(where: targetIDs.contains) }
        return mine.isEmpty && id == nil ? running : mine
    }

    /// The Stop chip's runs: the selection's, or every run while nothing is selected. A selection that is not running
    /// shows no Stop chip (it would read as stopping the selected files); ⌘. still stops every run then.
    var stopChipJobs: [TrayJob] {
        selection.isEmpty || selectedItems.contains(where: { job(for: $0.id) != nil }) ? stoppableJobs() : []
    }

    /// ⌘. / the Stop chip / "Stop" in the menu: cancels `stoppableJobs(id)`.
    func stopRunning(_ id: UUID? = nil) {
        for job in stoppableJobs(id) { cancel(job.id) }
    }

    /// ⌘⌫ with nothing selected: hides the error tiles of failed drops (they cannot be selected).
    func dismissFailedJobs() { jobs.removeAll { $0.failure != nil } }

    // MARK: Sharing (the shell anchors the sheets and gives focus back, R3 §7)

    func airDrop(_ id: UUID? = nil) {
        let list = urls(of: targets(for: id))
        guard !list.isEmpty else { return }
        let notch = notch
        Task { _ = await notch.presentAirDrop(list) }
    }

    /// Files dropped on an AirDrop zone go straight to the AirDrop sheet; they are not kept. The drop counts as taken
    /// whatever the user does in the sheet (a false result would make the shell keep the files in the Tray, §4.4), and
    /// the drop does not wait for the sheet. Temporary files (resolved promises from Photos, Safari or Mail, which the
    /// shell may delete once the drop returns) are first copied into a staging folder that lives until the sheet is
    /// done; `presentAirDrop` returns when sharing finished or failed.
    func airDrop(dropped urls: [URL]) async -> Bool {
        guard !urls.isEmpty else { return false }
        let folder = directories.work.appending(path: "\(UUID().uuidString)-airdrop", directoryHint: .isDirectory)
        let staged = await Self.stage(urls, storage: storage, into: folder)
        let notch = notch
        Task {
            _ = await notch.presentAirDrop(staged)
            await Self.removeFolder(folder)
        }
        return true
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
