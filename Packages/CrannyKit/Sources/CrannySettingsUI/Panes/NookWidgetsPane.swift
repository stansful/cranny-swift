// CrannySettingsUI/Panes/NookWidgetsPane.swift — Settings ▸ Layout & Widgets (code id `nook`, DESIGN.md §11.1): pages,
// the WYSIWYG grid editor of the selected page right under the stage (which shows that page live), and the widget
// library with per-widget options. Every change writes `CoreSettings.pages` at once (D14); a change that would not
// fit is refused with the overflow message and nothing is written.
import CrannyCore
import CrannyNotchUI
import Foundation
import SwiftUI

struct NookWidgetsPane: View {
    let registry: ModuleRegistry
    @Environment(StageController.self) private var stage: StageController?
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
                PageStrip(editor: editor, selection: Binding(get: { pageID }, set: { selection = $0 }), apply: apply)
                VStack(alignment: .leading, spacing: 8) {
                    GridEditor(page: page, editor: editor, registry: registry, theme: theme, apply: apply,
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
                WidgetLibraryList(registry: registry, page: page, editor: editor, apply: apply)
            } header: {
                Text(verbatim: LayoutRows.library.title)
            }
        }
        .onAppear { stage?.show(page: pageID) }
        .onChange(of: pageID) { _, page in
            refusal = nil
            stage?.show(page: page)
        }
    }

    /// The editor over the live pages, at the stage's maximum width.
    private var currentEditor: LayoutEditor {
        let pages = settings[CoreSettings.pages]
        let ids = Set(pages.flatMap { $0.items.map(\.widget) } + registry.widgets.map(\.id))
        let sizes = Dictionary(uniqueKeysWithValues: ids.map { ($0, KnownWidgets.info($0, registry: registry).sizes) })
        return LayoutEditor(pages: pages, maxColumns: maxColumns, sizes: sizes)
    }

    private var maxColumns: Int {
        stage?.model.layout.maxColumns
            ?? NotchLayout(metrics: .reference, grid: NookGrid(density: settings[CoreSettings.density], textSize: settings[CoreSettings.textSize],
                                                               style: settings[CoreSettings.widgetStyle],
                                                               paddingTune: CGFloat(settings[CoreSettings.panelPaddingTune]))).maxColumns
    }

    private var theme: CrannyTheme { stage?.model.theme ?? CrannyTheme() }

    /// Runs `change` on a copy; writes the pages when it succeeds, shows the refusal otherwise.
    private func apply(_ change: (inout LayoutEditor) -> LayoutEditor.Refusal?) {
        var editor = currentEditor
        if let refused = change(&editor) {
            refusal = refused
            registry.services.haptics.play(.alignment)
            AccessibilityNotification.Announcement(LayoutRows.message(for: refused)).post()
            return
        }
        refusal = nil
        if editor.pages != settings[CoreSettings.pages] { settings[CoreSettings.pages] = editor.pages }
    }
}

#Preview("Layout & Widgets") {
    NookWidgetsPane(registry: ModuleRegistry(services: .preview()))
        .frame(width: 650, height: 520)
}
