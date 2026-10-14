// CrannySettingsUI/Panes/PageStrip.swift — the pages of Layout & Widgets (DESIGN.md §6.2, §11.1): Home plus up to three
// user pages as selectable capsules; Add Page; and per page (context menu, also VoiceOver actions) Rename…, Symbol,
// Move Left / Right and Remove Page. Selecting a page edits it and shows it on the stage.
import CrannyCore
import Foundation
import SwiftUI

struct PageStrip: View {
    let editor: LayoutEditor
    @Binding var selection: PageID
    let apply: (_ change: (inout LayoutEditor) -> LayoutEditor.Refusal?) -> Void
    @State private var renaming: PageID?
    @State private var draftTitle = ""

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(editor.pages) { page in
                    PageCapsule(page: page, isSelected: page.id == selection) { selection = page.id }
                        .contextMenu { menu(for: page) }
                        .accessibilityAction(named: Text("Rename…", bundle: .module, comment: "Settings ▸ Layout & Widgets: rename a page")) { startRenaming(page) }
                }
                Button {
                    addPage()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(!editor.canAddPage)
                .help(Text("Add Page", bundle: .module, comment: "Settings ▸ Layout & Widgets: adds a user page"))
                .accessibilityLabel(Text("Add Page", bundle: .module, comment: "Settings ▸ Layout & Widgets: adds a user page"))
            }
        } label: {
            RowLabel(title: LayoutRows.pages.title,
                     footnote: String(localized: "Home and up to three pages of your own. Right-click a page to rename or remove it.",
                                      bundle: .module, comment: "Settings ▸ Layout & Widgets: footnote of Pages"))
        }
        .searchTarget(LayoutRows.pages)
        .alert(Text("Rename Page", bundle: .module, comment: "Settings ▸ Layout & Widgets: rename alert title"),
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(text: $draftTitle) {
                Text("Name", bundle: .module, comment: "Settings ▸ Layout & Widgets: page name field")
            }
            Button {
                if let renaming { apply { $0.rename(renaming, to: draftTitle); return nil } }
                renaming = nil
            } label: {
                Text("Rename", bundle: .module, comment: "Settings ▸ Layout & Widgets: confirm button of the rename alert")
            }
            Button(role: .cancel) { renaming = nil } label: {
                Text("Cancel", bundle: .module, comment: "Settings: cancel button of a confirmation")
            }
        }
    }

    @ViewBuilder private func menu(for page: NookPage) -> some View {
        Button { startRenaming(page) } label: {
            Text("Rename…", bundle: .module, comment: "Settings ▸ Layout & Widgets: rename a page")
        }
        Menu {
            ForEach(LayoutRows.pageSymbols, id: \.self) { symbol in
                Button {
                    apply { $0.rename(page.id, to: page.title ?? "", symbol: symbol); return nil }
                } label: {
                    Image(systemName: symbol)
                }
            }
        } label: {
            Text("Symbol", bundle: .module, comment: "Settings ▸ Layout & Widgets: submenu that picks a page's glyph")
        }
        Divider()
        Button { apply { $0.movePage(page.id, by: -1); return nil } } label: {
            Text("Move left", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place left")
        }
        .disabled(editor.pages.first?.id == page.id)
        Button { apply { $0.movePage(page.id, by: 1); return nil } } label: {
            Text("Move right", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place right")
        }
        .disabled(editor.pages.last?.id == page.id)
        if page.id != .nook {
            Divider()
            Button(role: .destructive) {
                if selection == page.id { selection = .nook }
                apply { $0.removePage(page.id); return nil }
            } label: {
                Text("Remove Page", bundle: .module, comment: "Settings ▸ Layout & Widgets: removes a user page (its widgets stay available)")
            }
        }
    }

    private func startRenaming(_ page: NookPage) {
        draftTitle = LayoutRows.title(of: page)
        renaming = page.id
    }

    private func addPage() {
        let number = editor.userPageCount + 2
        let title = String(localized: "Page \(number)", bundle: .module, comment: "Settings ▸ Layout & Widgets: default name of a new page; the argument is its number")
        let id = PageID("page.\(UUID().uuidString)")
        apply { editor in
            switch editor.addPage(title: title, symbol: "sparkles", id: id) {
            case .success: return nil
            case .failure(let refusal): return refusal
            }
        }
        selection = id
    }
}

/// One page as a capsule: glyph and name, selected = filled.
private struct PageCapsule: View {
    let page: NookPage
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label {
                Text(verbatim: LayoutRows.title(of: page)).lineLimit(1)
            } icon: {
                Image(systemName: page.symbol)
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
            .overlay(Capsule(style: .continuous).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Pages") {
    @Previewable @State var selection: PageID = .nook
    let editor = LayoutEditor(pages: [NookPreset.listener.page, NookPage(id: "page.focus", title: "Focus", symbol: "note.text", items: [])],
                              maxColumns: 12, sizes: [:])
    Form { PageStrip(editor: editor, selection: $selection, apply: { _ in }) }
        .formStyle(.grouped)
        .frame(width: 650, height: 140)
}
