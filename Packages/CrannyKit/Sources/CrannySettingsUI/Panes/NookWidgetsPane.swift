// CrannySettingsUI/Panes/NookWidgetsPane.swift — Settings ▸ Layout & Widgets (code id `nook`, DESIGN.md §11.1): pages,
// the WYSIWYG grid editor of the selected page right under the stage (which shows that page live), and the widget
// library with per-widget options. Every change writes `CoreSettings.pages` at once (D14); a change that would not
// fit is refused with the overflow message and nothing is written. Opened at a widget's library entry (search, a deep
// link, Keyboard's capture warning), it shows a page that holds the widget or has room for it, so Add works there.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

struct NookWidgetsPane: View {
    let registry: ModuleRegistry
    @Environment(StageController.self) private var stage: StageController?
    @Environment(SettingsNavigator.self) private var navigator: SettingsNavigator?
    @State private var selection: PageID?
    @State private var refusal: LayoutEditor.Refusal?
    @State private var optionsWidget: WidgetID?

    private var settings: SettingsStore { registry.services.settings }

    var body: some View {
        let editor = currentEditor
        let pageID = selection.flatMap { editor.page($0)?.id } ?? editor.pages.first?.id ?? .nook
        let page = editor.page(pageID) ?? NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: [])
        SettingsForm(.nookAndWidgets) {
            Section {
                PageStrip(editor: editor, selection: Binding(get: { pageID }, set: { selection = $0 }), apply: commit)
                VStack(alignment: .leading, spacing: 8) {
                    GridEditor(page: page, editor: editor, registry: registry, theme: theme, apply: commit,
                               showOptions: { optionsWidget = $0 })
                    Text(verbatim: refusal.map(LayoutRows.message(for:))
                         ?? String(localized: "Drag to reorder, drag the right edge to resize. ⌥← ⌥→ move the selected widget, ⌥⇧← ⌥⇧→ resize it.",
                                   bundle: .module, comment: "Settings ▸ Layout & Widgets: footnote of the grid editor"))
                        .font(.footnote)
                        .foregroundStyle(refusal == nil ? Color.secondary : Color.red)
                        .accessibilityAddTraits(refusal == nil ? [] : .updatesFrequently)
                }
                .searchTarget(LayoutRows.layout)
                .popover(isPresented: Binding(get: { optionsWidget != nil }, set: { if !$0 { optionsWidget = nil } })) {
                    if let id = optionsWidget, let widget = registry.widget(id) { WidgetOptionsPopover(widget: widget) }
                }
            } header: {
                Text(verbatim: LayoutRows.layout.title)
            }
            Section {
                WidgetLibraryList(registry: registry, page: page, editor: editor, apply: commit)
            } header: {
                Text(verbatim: LayoutRows.library.title)
            }
        }
        .onAppear {
            let shown = requestedPage(current: pageID) ?? pageID
            if shown != pageID { selection = shown }
            stage?.show(page: shown)
            stage?.setOpenMode(.editLayout)
        }
        .onDisappear { stage?.setOpenMode(.grid) }
        .onChange(of: navigator?.highlightSerial) {
            if let page = requestedPage(current: pageID), page != pageID { selection = page }
        }
        .onChange(of: pageID) { _, page in
            refusal = nil
            stage?.show(page: page)
        }
    }

    /// The editor over the live pages, at the stage's maximum width.
    private var currentEditor: LayoutEditor { .live(registry: registry, stage: stage) }

    /// A fresh request for a widget's library entry: the page that holds the widget or has room for it (nil: keep
    /// the page shown).
    private func requestedPage(current: PageID) -> PageID? {
        guard let navigator, navigator.isHighlightFresh, let row = navigator.highlightedRow,
              let widget = LayoutRows.widgetID(inRow: row) else { return nil }
        return currentEditor.page(for: widget, preferring: current)
    }

    private var theme: CrannyTheme { stage?.model.theme ?? CrannyTheme() }

    private var commit: LayoutCommit { LayoutCommit(perform: apply) }

    /// Runs `change` on a copy; writes the pages when it succeeds (true), shows and announces the refusal otherwise.
    private func apply(_ change: (inout LayoutEditor) -> LayoutEditor.Refusal?) -> Bool {
        var editor = currentEditor
        if let refused = change(&editor) {
            refusal = refused
            registry.services.haptics.play(.alignment)
            AccessibilityNotification.Announcement(LayoutRows.message(for: refused)).post()
            return false
        }
        refusal = nil
        if editor.pages != settings[CoreSettings.pages] { settings[CoreSettings.pages] = editor.pages }
        return true
    }
}

extension LayoutEditor {
    /// The editor over the live pages (`CoreSettings.pages`) with each placed or registered widget's sizes, as wide
    /// as the stage's display allows (`NotchLayout.maxColumns`; the reference display until the stage exists).
    /// Layout & Widgets edits through it; Keyboard's capture warning asks it whether a widget has room.
    static func live(registry: ModuleRegistry, stage: StageController?) -> LayoutEditor {
        let settings = registry.services.settings
        let pages = settings[CoreSettings.pages]
        let ids = Set(pages.flatMap { $0.items.map(\.widget) } + registry.widgets.map(\.id))
        let sizes = Dictionary(uniqueKeysWithValues: ids.map { ($0, KnownWidgets.info($0, registry: registry).sizes) })
        let maxColumns = stage?.model.layout.maxColumns
            ?? NotchLayout(metrics: .reference, grid: NookGrid(density: settings[CoreSettings.density], textSize: settings[CoreSettings.textSize],
                                                               style: settings[CoreSettings.widgetStyle],
                                                               paddingTune: CGFloat(settings[CoreSettings.panelPaddingTune]))).maxColumns
        return LayoutEditor(pages: pages, maxColumns: maxColumns, sizes: sizes)
    }
}

#Preview("Layout & Widgets") {
    NookWidgetsPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 520)
}
