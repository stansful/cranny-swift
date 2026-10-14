// CrannySettingsUI/Sidebar/SettingsNavigator.swift — which pane is shown and which row a search result or a
// deep link asked for (DESIGN.md §11.3: "picking a result opens the pane, scrolls to the row and highlights it").
// A deep link is a `SettingsPageID` whose raw value carries a row after "#": `general#hoverDelay` opens
// General, scrolls to "Hover delay" and washes it with the accent. `AppControl.openSettings(_:)` and the
// Debug `--qa-settings` hook accept it unchanged, so no Core API is needed.
import CrannyCore
import Foundation
import Observation

@MainActor @Observable final class SettingsNavigator {
    /// The pane in the detail column.
    var selection: SettingsPageID
    /// The row to scroll to; `SettingsForm` consumes it once the pane's rows exist.
    private(set) var pendingRow: String?
    /// The row to wash with the accent, bumped on every request so a repeat flashes again.
    private(set) var highlightedRow: String?
    private(set) var highlightSerial = 0
    @ObservationIgnored private(set) var highlightDate = Date.distantPast

    init(target: SettingsPageID? = nil) {
        let parsed = Self.parse(target)
        selection = parsed.pane ?? .general
        if let row = parsed.row { reveal(row) }
    }

    /// Opens a pane or a deep link ("general#hoverDelay"); nil keeps the current pane.
    func open(_ target: SettingsPageID?) {
        let parsed = Self.parse(target)
        if let pane = parsed.pane, pane != selection { selection = pane }
        if let row = parsed.row { reveal(row) }
    }

    /// Opens `row`'s pane, scrolls to it and highlights it.
    func open(row: SettingsRowInfo) {
        if selection != row.pane { selection = row.pane }
        reveal(row.id)
    }

    /// Called by `pane`'s form: returns the row to scroll to if it belongs to that pane (at most once per request).
    func takePendingRow(in pane: SettingsPageID) -> String? {
        guard let row = pendingRow, row.hasPrefix(pane.rawValue + ".") else { return nil }
        pendingRow = nil
        return row
    }

    private func reveal(_ row: String) {
        pendingRow = row
        highlightedRow = row
        highlightDate = Date()
        highlightSerial += 1
    }

    // MARK: Deep links (pure, tested)

    /// "general#hoverDelay" → (general, "general.hoverDelay"); "about" → (about, nil); nil → (nil, nil).
    static func parse(_ target: SettingsPageID?) -> (pane: SettingsPageID?, row: String?) {
        guard let raw = target?.rawValue, !raw.isEmpty else { return (nil, nil) }
        let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pane = SettingsPageID(String(parts[0]))
        guard parts.count == 2, !parts[1].isEmpty else { return (pane, nil) }
        return (pane, "\(pane.rawValue).\(parts[1])")
    }
}
