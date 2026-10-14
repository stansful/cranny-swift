// CrannySettingsUI/Panes/WidgetLibrary.swift — the widget library of Layout & Widgets (DESIGN.md §11.1): every registered
// widget with its one-line description and widths, an Add button for the page being edited (refused with the
// overflow when it does not fit) and its options (`NookWidget.makeOptions()`) in a popover. The same list opens from
// the editor's "+" tile.
import CrannyCore
import Foundation
import SwiftUI

struct WidgetLibraryList: View {
    let registry: ModuleRegistry
    let page: NookPage
    let editor: LayoutEditor
    let apply: (_ change: (inout LayoutEditor) -> LayoutEditor.Refusal?) -> Void
    /// Popover form: rows are buttons and options are not offered.
    var compact = false

    var body: some View {
        if registry.widgets.isEmpty {
            Text("No widgets are available yet.", bundle: .module, comment: "Settings ▸ Layout & Widgets: no module registered a widget")
                .foregroundStyle(.secondary)
                .padding(compact ? 16 : 0)
        } else if compact {
            List(registry.widgets) { widget in
                LibraryRow(widget: widget, page: page, editor: editor, apply: apply, compact: true)
            }
            .listStyle(.inset)
        } else {
            ForEach(registry.widgets) { widget in
                LibraryRow(widget: widget, page: page, editor: editor, apply: apply, compact: false)
                    .searchTarget(LayoutRows.widget(widget.id, title: widget.title))
            }
        }
    }
}

private struct LibraryRow: View {
    let widget: AnyNookWidget
    let page: NookPage
    let editor: LayoutEditor
    let apply: (_ change: (inout LayoutEditor) -> LayoutEditor.Refusal?) -> Void
    let compact: Bool
    @State private var showsOptions = false

    var body: some View {
        let isOnPage = page.items.contains { $0.widget == widget.id }
        HStack(spacing: 10) {
            Image(systemName: widget.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: widget.title)
                Text(verbatim: widget.summary + " · " + Self.widths(widget.sizes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if widget.hasOptions && !compact {
                Button {
                    showsOptions = true
                } label: {
                    Text("Options…", bundle: .module, comment: "Settings ▸ Layout & Widgets: opens a widget's options")
                }
                .popover(isPresented: $showsOptions, arrowEdge: .trailing) {
                    WidgetOptionsPopover(widget: widget)
                }
            }
            if isOnPage {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("On this page", bundle: .module, comment: "Settings ▸ Layout & Widgets: the widget is already on the page"))
            } else {
                Button {
                    apply { $0.add(widget.id, to: page.id) }
                } label: {
                    Text("Add", bundle: .module, comment: "Settings ▸ Layout & Widgets: adds a widget to the page")
                }
                .accessibilityLabel(Text("Add \(widget.title)", bundle: .module,
                                         comment: "Settings ▸ Layout & Widgets: VoiceOver label of Add; the argument is a widget name"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "2–3 cells" or "2 cells".
    static func widths(_ sizes: WidgetSizes) -> String {
        sizes.minimum == sizes.maximum ? LayoutRows.cells(sizes.minimum)
            : String(localized: "\(sizes.minimum)–\(sizes.maximum) cells", bundle: .module,
                     comment: "Settings ▸ Layout & Widgets: the widths a widget allows; arguments are the minimum and maximum")
    }
}

/// A widget's options (`makeOptions()`), in a small grouped form.
struct WidgetOptionsPopover: View {
    let widget: AnyNookWidget
    var body: some View {
        Form {
            Section {
                widget.makeOptions()
            } header: {
                Text(verbatim: widget.title)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .frame(minHeight: 140)
    }
}

#Preview("Widget library") {
    let registry = ModuleRegistry(services: .preview())
    let page = NookPreset.listener.page
    Form {
        WidgetLibraryList(registry: registry, page: page,
                          editor: LayoutEditor(pages: [page], maxColumns: 12, sizes: [:]), apply: { _ in })
    }
    .formStyle(.grouped)
    .frame(width: 600, height: 200)
}
