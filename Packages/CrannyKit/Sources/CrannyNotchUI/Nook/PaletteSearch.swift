// CrannyNotchUI/Nook/PaletteSearch.swift — ranking and selection of the ⌘K palette (DESIGN.md §6.4), pure and
// unit-tested. Providers filter their own commands (`PaletteCommandProvider.commands(matching:)`, in-memory);
// the palette orders the union so the best match is first and ↑ ↓ move through a window of visible rows.
import CrannyCore
import Foundation

nonisolated enum PaletteSearch {
    /// How well `title` (or a keyword) matches `query`: 0 title prefix · 1 word prefix in the title ·
    /// 2 keyword prefix · 3 anywhere · nil no match. An empty query matches everything at 3.
    static func score(title: String, keywords: [String], query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 3 }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if title.range(of: q, options: options.union(.anchored)) != nil { return 0 }
        let words = title.split(whereSeparator: { $0 == " " || $0 == "-" })
        if words.contains(where: { $0.range(of: q, options: options.union(.anchored)) != nil }) { return 1 }
        if keywords.contains(where: { $0.range(of: q, options: options.union(.anchored)) != nil }) { return 2 }
        if title.range(of: q, options: options) != nil || keywords.contains(where: { $0.range(of: q, options: options) != nil }) {
            return 3
        }
        return nil
    }

    /// Indices of `items` (title, keywords) in result order: by score, then by the providers' own order.
    static func order(_ items: [(title: String, keywords: [String])], query: String) -> [Int] {
        var scored: [(index: Int, score: Int)] = []
        for (index, item) in items.enumerated() {
            if let score = score(title: item.title, keywords: item.keywords, query: query) {
                scored.append((index, score))
            }
        }
        scored.sort { lhs, rhs in lhs.score != rhs.score ? lhs.score < rhs.score : lhs.index < rhs.index }
        return scored.map(\.index)
    }
}

/// The highlighted row and the window of visible rows.
nonisolated struct PaletteSelection: Equatable, Sendable {
    var index = 0
    var firstVisible = 0

    /// Moves by `delta` rows within `count` results, scrolling the `visible`-row window to keep it in view.
    mutating func move(by delta: Int, count: Int, visible: Int) {
        guard count > 0 else { self = PaletteSelection(); return }
        index = min(max(index + delta, 0), count - 1)
        clamp(count: count, visible: visible)
    }

    /// After the results changed: keep the index valid and the window around it.
    mutating func clamp(count: Int, visible: Int) {
        guard count > 0 else { self = PaletteSelection(); return }
        index = min(max(index, 0), count - 1)
        let rows = max(visible, 1)
        if index < firstVisible { firstVisible = index }
        if index >= firstVisible + rows { firstVisible = index - rows + 1 }
        firstVisible = min(max(firstVisible, 0), max(count - rows, 0))
    }

    /// Rows that fit a grid area of `height`: the field, a gap, then rows (DESIGN.md §6.4: up to 4).
    static func visibleRows(height: CGFloat) -> Int {
        let m = PaletteMetrics.self
        return min(max(Int((height - m.fieldHeight - m.gap) / m.rowHeight), 1), m.maximumRows)
    }
}

/// The ⌘K palette's measures (DESIGN.md §6.4).
nonisolated enum PaletteMetrics {
    /// The search field (in a `well`, r 8).
    static let fieldHeight: CGFloat = 28
    /// Between the field and the first row.
    static let gap: CGFloat = Space.xs
    /// One result row.
    static let rowHeight: CGFloat = 22
    /// A row's icon box.
    static let iconSize: CGFloat = 16
    /// Rows shown at most.
    static let maximumRows = 4
}
