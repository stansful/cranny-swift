// CrannySettingsUI/Panes/LayoutEditor.swift — the pure model behind Settings ▸ Layout & Widgets (DESIGN.md §6.3, §6.6,
// §11.1): pages (Home plus up to 3 user pages: add, rename, reorder, remove) and their widgets (add, remove, reorder,
// resize in whole cells within each widget's sizes). A change that would make a page wider than the Nook's maximum
// columns is refused with the overflow ("2 cells over"), never clipped: the Nook never scrolls sideways. Tested.
import CrannyCore
import Foundation

struct LayoutEditor: Equatable {
    /// Users can add up to three pages (DESIGN.md §6.2).
    static let maxUserPages = 3

    /// Why a change was refused.
    nonisolated enum Refusal: Equatable, Error {
        /// The page would need `cells` more columns than fit.
        case overflow(cells: Int)
        case pageLimit
    }

    var pages: [NookPage]
    /// The widest page the Nook can show, in cells (`NotchLayout.maxColumns`).
    let maxColumns: Int
    private let sizes: [WidgetID: WidgetSizes]

    /// `sizes` gives each widget's allowed widths (registered or from the design's table).
    init(pages: [NookPage], maxColumns: Int, sizes: [WidgetID: WidgetSizes]) {
        self.pages = pages; self.maxColumns = maxColumns; self.sizes = sizes
    }

    static func == (a: Self, b: Self) -> Bool { a.pages == b.pages && a.maxColumns == b.maxColumns }

    func sizes(of widget: WidgetID) -> WidgetSizes { sizes[widget] ?? WidgetSizes(minimum: 1, preferred: 2, maximum: 8) }

    // MARK: Cells

    func page(_ id: PageID) -> NookPage? { pages.first { $0.id == id } }

    /// Columns the page uses (each widget clamped to its sizes, as the Nook draws it).
    func usedCells(on page: PageID) -> Int {
        (self.page(page)?.items ?? []).reduce(0) { $0 + sizes(of: $1.widget).clamp($1.cells) }
    }

    func cellsLeft(on page: PageID) -> Int { maxColumns - usedCells(on: page) }

    // MARK: Widgets

    /// Adds `widget` at its preferred width, or narrower down to its minimum when space is short.
    mutating func add(_ widget: WidgetID, to page: PageID) -> Refusal? {
        guard let p = index(of: page), !pages[p].items.contains(where: { $0.widget == widget }) else { return nil }
        let size = sizes(of: widget)
        let left = cellsLeft(on: page)
        guard left >= size.minimum else { return .overflow(cells: size.minimum - left) }
        pages[p].items.append(NookItem(widget, cells: min(size.preferred, left)))
        return nil
    }

    mutating func remove(_ widget: WidgetID, from page: PageID) {
        guard let p = index(of: page) else { return }
        pages[p].items.removeAll { $0.widget == widget }
    }

    /// Moves `widget` to `destination` (an index in the page's items after removal).
    mutating func move(_ widget: WidgetID, on page: PageID, to destination: Int) {
        guard let p = index(of: page), let from = pages[p].items.firstIndex(where: { $0.widget == widget }) else { return }
        let item = pages[p].items.remove(at: from)
        pages[p].items.insert(item, at: min(max(destination, 0), pages[p].items.count))
    }

    /// ⌥← / ⌥→: one place left (−1) or right (+1).
    mutating func shift(_ widget: WidgetID, on page: PageID, by offset: Int) {
        guard let p = index(of: page), let from = pages[p].items.firstIndex(where: { $0.widget == widget }) else { return }
        move(widget, on: page, to: from + offset)
    }

    /// Sets the width, clamped to the widget's sizes; refuses a width that does not fit.
    mutating func resize(_ widget: WidgetID, on page: PageID, to cells: Int) -> Refusal? {
        guard let p = index(of: page), let i = pages[p].items.firstIndex(where: { $0.widget == widget }) else { return nil }
        let size = sizes(of: widget)
        let current = size.clamp(pages[p].items[i].cells)
        let target = size.clamp(cells)
        let over = usedCells(on: page) - current + target - maxColumns
        if target > current && over > 0 { return .overflow(cells: over) }
        pages[p].items[i].cells = target
        return nil
    }

    func cells(of widget: WidgetID, on page: PageID) -> Int? {
        self.page(page)?.items.first { $0.widget == widget }.map { sizes(of: widget).clamp($0.cells) }
    }

    // MARK: Pages

    var userPageCount: Int { pages.filter { $0.id != .nook }.count }
    var canAddPage: Bool { userPageCount < Self.maxUserPages }

    /// Adds an empty user page ("page.<uuid>") and returns its id.
    mutating func addPage(title: String, symbol: String, id: PageID = PageID("page.\(UUID().uuidString)")) -> Result<PageID, Refusal> {
        guard canAddPage else { return .failure(.pageLimit) }
        pages.append(NookPage(id: id, title: title, symbol: symbol, items: []))
        return .success(id)
    }

    /// Renames a page; an empty title gives the built-in page back its localized name.
    mutating func rename(_ page: PageID, to title: String, symbol: String? = nil) {
        guard let p = index(of: page) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[p].title = trimmed.isEmpty && page == .nook ? nil : (trimmed.isEmpty ? pages[p].title : trimmed)
        if let symbol { pages[p].symbol = symbol }
    }

    /// Removes a user page (Home stays).
    mutating func removePage(_ page: PageID) {
        guard page != .nook else { return }
        pages.removeAll { $0.id == page }
    }

    /// Moves a page one place left (−1) or right (+1).
    mutating func movePage(_ page: PageID, by offset: Int) {
        guard let from = index(of: page) else { return }
        let to = min(max(from + offset, 0), pages.count - 1)
        guard to != from else { return }
        pages.insert(pages.remove(at: from), at: to)
    }

    private func index(of page: PageID) -> Int? { pages.firstIndex { $0.id == page } }
}
