// CrannySettingsUI/Panes/LayoutRows.swift — the rows of Settings ▸ Layout & Widgets and its shared strings.
import CrannyCore
import Foundation

enum LayoutRows {
    static var pages: SettingsRowInfo {
        SettingsRowInfo(.nookAndWidgets, "pages",
                        title: String(localized: "Pages", bundle: .module, comment: "Settings ▸ Layout & Widgets: the page tabs (Home and user pages)"),
                        keywords: [String(localized: "tabs", bundle: .module, comment: "Settings search: keyword for pages")])
    }
    static var layout: SettingsRowInfo {
        SettingsRowInfo(.nookAndWidgets, "layout",
                        title: String(localized: "Layout", bundle: .module, comment: "Settings ▸ Layout & Widgets: the grid editor (glossary: раскладка)"),
                        keywords: [String(localized: "resize", bundle: .module, comment: "Settings search: keyword for the layout editor"),
                                   String(localized: "reorder", bundle: .module, comment: "Settings search: keyword for the layout editor")])
    }
    static var library: SettingsRowInfo {
        SettingsRowInfo(.nookAndWidgets, "library",
                        title: String(localized: "Widget library", bundle: .module, comment: "Settings ▸ Layout & Widgets: section header"),
                        keywords: [String(localized: "add widget", bundle: .module, comment: "Settings search: keyword for the widget library")])
    }

    /// One row per registered widget (its library entry), so "calendar" finds Layout & Widgets.
    static func widget(_ id: WidgetID, title: String) -> SettingsRowInfo {
        SettingsRowInfo(.nookAndWidgets, "widget.\(id.rawValue)", title: title)
    }

    static func all(registry: ModuleRegistry) -> [SettingsRowInfo] {
        [pages, layout, library] + registry.widgets.map { widget($0.id, title: $0.title) }
    }

    /// "Home": the built-in page's name (code id `nook`; "Nook" never appears in UI text, D20).
    static var homeTitle: String {
        String(localized: "Home", bundle: .module, comment: "Settings ▸ Layout & Widgets: the built-in widget page (glossary: Главная)")
    }

    static func title(of page: NookPage) -> String { page.title ?? homeTitle }

    /// Glyphs a user page can wear (DESIGN.md §14.1).
    static let pageSymbols = ["square.grid.2x2.fill", "sparkles", "note.text", "checklist", "timer", "calendar", "music.note", "folder"]

    /// "2 cells over; move a widget to another page" (DESIGN.md §6.3).
    static func message(for refusal: LayoutEditor.Refusal) -> String {
        switch refusal {
        case .overflow(let cells):
            String(localized: "\(cells) cells over; move a widget to another page.", bundle: .module,
                   comment: "Settings ▸ Layout & Widgets: a change would not fit; the argument is the number of extra cells (plural)")
        case .pageLimit:
            String(localized: "You can add up to three pages.", bundle: .module, comment: "Settings ▸ Layout & Widgets: the page limit is reached")
        }
    }

    /// "4 cells"
    static func cells(_ count: Int) -> String {
        String(localized: "\(count) cells", bundle: .module, comment: "Settings ▸ Layout & Widgets: a widget's width in grid cells (plural)")
    }
}
