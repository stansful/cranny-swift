// CrannySettingsUI/Sidebar/SettingsSearchIndex.swift — search over pane names, row labels and localized keywords
// (DESIGN.md §11.3: "volume" → HUD, "external monitor" → displays, "dock" → Quick Apps). Shell panes are indexed
// by their rows (`SettingsRowInfo`, the same strings the rows show); module panes are opaque views, so they are
// indexed by the `keywords` they declare plus a few well-known aliases (`KnownPaneKeywords`).
//
// Matching is case-, diacritic- and width-insensitive ("е" finds "ё"), and every word of the query must start a
// word of the entry ("ext mon" finds "external monitor"; "on" does not find "Reset").
import CrannyCore
import Foundation

struct SettingsSearchIndex {
    /// What a query found, in sidebar order.
    struct Results: Equatable {
        /// Panes whose name or keywords match, or that contain a matching row.
        var panes: [SettingsPageID]
        /// Matching rows of shell panes.
        var rows: [SettingsRowInfo]
        var isEmpty: Bool { panes.isEmpty && rows.isEmpty }
    }

    private struct PaneEntry {
        let id: SettingsPageID
        let words: [String]
    }

    private struct RowEntry {
        let info: SettingsRowInfo
        let words: [String]
    }

    private let panes: [PaneEntry]
    private let rows: [RowEntry]

    /// `pages` in sidebar order; `rows` of the shell panes; `aliases` add terms to panes that exist.
    init(pages: [SettingsPage], rows: [SettingsRowInfo], aliases: [SettingsPageID: [String]] = [:]) {
        panes = pages.map { page in
            PaneEntry(id: page.id, words: Self.words(in: [page.title] + page.keywords + (aliases[page.id] ?? [])))
        }
        let order = Dictionary(pages.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.rows = rows
            .filter { order[$0.pane] != nil }
            .enumerated()
            .sorted { (order[$0.element.pane] ?? 0, $0.offset) < (order[$1.element.pane] ?? 0, $1.offset) }
            .map { RowEntry(info: $0.element, words: Self.words(in: [$0.element.title] + $0.element.keywords)) }
    }

    func search(_ query: String) -> Results {
        let tokens = Self.words(in: [query])
        guard !tokens.isEmpty else { return Results(panes: panes.map(\.id), rows: []) }
        let rowHits = rows.filter { Self.matches($0.words, tokens) }.map(\.info)
        let panesWithRows = Set(rowHits.map(\.pane))
        let paneHits = panes.filter { Self.matches($0.words, tokens) || panesWithRows.contains($0.id) }.map(\.id)
        return Results(panes: paneHits, rows: rowHits)
    }

    // MARK: Matching (pure)

    /// Every query token is a prefix of some word.
    static func matches(_ words: [String], _ tokens: [String]) -> Bool {
        tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
    }

    /// Folded words of `texts`: lowercased, without diacritics or width variants, split at non-alphanumerics.
    static func words(in texts: [String]) -> [String] {
        texts.flatMap { text in
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        }
    }
}
