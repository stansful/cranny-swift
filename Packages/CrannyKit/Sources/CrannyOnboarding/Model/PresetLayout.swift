// CrannyOnboarding/Model/PresetLayout.swift — step 4's starting layouts (`NookPreset`) against the stored
// pages (pure). Picking a preset rewrites only the Home page; user pages stay (DESIGN.md §12.1).
import CrannyCore
import Foundation

nonisolated enum PresetLayout {
    /// The built-in grid page ("Home"; code id `nook`, ARCHITECTURE.md D20).
    static func home(in pages: [NookPage]) -> NookPage? {
        pages.first { $0.id == .nook }
    }

    /// The items on Home, or the default preset's when there is no Home page.
    static func homeItems(_ pages: [NookPage]) -> [NookItem] {
        home(in: pages)?.items ?? NookPreset.listener.items
    }

    /// The preset Home currently equals, if any (a customised layout matches none).
    static func matching(_ pages: [NookPage]) -> NookPreset? {
        let items = homeItems(pages)
        return NookPreset.allCases.first { $0.items == items }
    }

    /// `pages` with Home's items replaced by the preset's. Home keeps its place, title and symbol; user
    /// pages are untouched. Without a Home page, the preset's page is inserted first.
    static func applying(_ preset: NookPreset, to pages: [NookPage]) -> [NookPage] {
        guard let index = pages.firstIndex(where: { $0.id == .nook }) else { return [preset.page] + pages }
        var result = pages
        result[index].items = preset.items
        return result
    }

    /// Width of Home in grid cells, each item clamped to its widget's sizes when the widget is registered.
    static func columns(of items: [NookItem], sizes: [WidgetID: WidgetSizes]) -> Int {
        let total = items.reduce(0) { sum, item in sum + (sizes[item.widget]?.clamp(item.cells) ?? max(item.cells, 1)) }
        return max(total, 1)
    }

    /// The features a layout uses: the modules of its widgets.
    static func modules(of items: [NookItem]) -> Set<ModuleID> {
        Set(items.map { ModuleID(String($0.widget.rawValue.prefix { $0 != "." })) })
    }
}
