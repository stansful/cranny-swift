// CrannyNotchUI/Nook/LayoutEditing.swift — the rules of the layout editor (DESIGN.md §6.3, §6.6), pure and
// unit-tested: move, resize in whole cells within the widget's sizes and the page's maximum columns, add,
// remove, and where a dragged card lands. The editor and the card's ⋯ menu change a copy of
// `CoreSettings.pages` and hand it to `NotchUIActions.commitLayout`; NotchUI never writes settings.
import CrannyCore
import Foundation

nonisolated struct LayoutEditing: Equatable, Sendable {
    /// Every page (`CoreSettings.pages`).
    var pages: [NookPage]
    /// The page being edited.
    var pageID: PageID
    /// `NotchLayout.maxColumns` of the display: a page never grows beyond it (the Nook never scrolls).
    var maxColumns: Int

    var items: [NookItem] { pages.first { $0.id == pageID }?.items ?? [] }
    /// Cells in use (each item counted at its stored width; the owner clamps them to the widget's sizes).
    var usedColumns: Int { items.reduce(0) { $0 + max($1.cells, 1) } }
    /// "N cells left" (negative = over the limit).
    var cellsLeft: Int { maxColumns - usedColumns }

    // MARK: Changes (each returns nil when refused or a no-op)

    /// Moves the item at `index` by `offset` places (⌥← / ⌥→, drag to reorder).
    func moving(from index: Int, to target: Int) -> LayoutEditing? {
        var copy = self
        guard copy.updateItems({ items in
            guard items.indices.contains(index) else { return false }
            let clamped = min(max(target, 0), items.count - 1)
            guard clamped != index else { return false }
            let item = items.remove(at: index)
            items.insert(item, at: clamped)
            return true
        }) else { return nil }
        return copy
    }

    /// Resizes the item at `index` to `cells`, clamped to `sizes` and to the room left on the page.
    func resizing(at index: Int, to cells: Int, sizes: WidgetSizes?) -> LayoutEditing? {
        var copy = self
        guard copy.updateItems({ items in
            guard items.indices.contains(index) else { return false }
            let current = max(items[index].cells, 1)
            let others = items.enumerated().reduce(0) { $0 + ($1.offset == index ? 0 : max($1.element.cells, 1)) }
            let room = maxColumns - others
            let allowed = sizes.map { $0.clamp(cells) } ?? max(cells, 1)
            let next = min(allowed, max(room, sizes?.minimum ?? 1))
            guard next != current, next >= 1 else { return false }
            items[index].cells = next
            return true
        }) else { return nil }
        return copy
    }

    /// Adds `widget` at its preferred width (or the room left, if at least its minimum). Refused when it does
    /// not fit ("N cells over") or is already on the page.
    func adding(_ widget: WidgetID, sizes: WidgetSizes) -> LayoutEditing? {
        guard !items.contains(where: { $0.widget == widget }) else { return nil }
        let cells = min(sizes.preferred, cellsLeft)
        guard cells >= sizes.minimum else { return nil }
        var copy = self
        _ = copy.updateItems { items in items.append(NookItem(widget, cells: cells)); return true }
        return copy
    }

    /// How many cells `widget` would be over the limit at its minimum width (0 = it fits).
    func overflow(adding sizes: WidgetSizes) -> Int { max(sizes.minimum - cellsLeft, 0) }

    func removing(_ widget: WidgetID) -> LayoutEditing? {
        var copy = self
        guard copy.updateItems({ items in
            let before = items.count
            items.removeAll { $0.widget == widget }
            return items.count != before
        }) else { return nil }
        return copy
    }

    /// Where a card dragged by `translation` (pt) lands: the slot whose centre the dragged card's centre passes.
    static func dropIndex(widths: [CGFloat], gutter: CGFloat, from index: Int, translation: CGFloat) -> Int {
        guard widths.indices.contains(index) else { return index }
        var starts: [CGFloat] = []
        var x: CGFloat = 0
        for w in widths { starts.append(x); x += w + gutter }
        let centre = starts[index] + widths[index] / 2 + translation
        var target = index
        if translation > 0 {
            for j in (index + 1)..<widths.count where centre > starts[j] + widths[j] / 2 { target = j }
        } else if translation < 0 {
            for j in stride(from: index - 1, through: 0, by: -1) where centre < starts[j] + widths[j] / 2 { target = j }
        }
        return target
    }

    /// Whole cells a resize handle dragged by `translation` (pt) adds or removes (one cell = cell + gutter).
    static func cellDelta(translation: CGFloat, cell: CGFloat, gutter: CGFloat) -> Int {
        let step = max(cell + gutter, 1)
        return Int((translation / step).rounded())
    }

    private mutating func updateItems(_ change: (inout [NookItem]) -> Bool) -> Bool {
        guard let p = pages.firstIndex(where: { $0.id == pageID }) else { return false }
        var items = pages[p].items
        guard change(&items) else { return false }
        pages[p].items = items
        return true
    }
}
