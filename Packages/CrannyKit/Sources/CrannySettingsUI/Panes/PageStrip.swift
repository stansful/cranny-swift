// CrannySettingsUI/Panes/PageStrip.swift — the pages of Layout & Widgets (DESIGN.md §6.2, §11.1): Home plus up to three
// user pages as selectable capsules; Add Page; and per page Rename…, Symbol, Move left / right and Remove Page. Every
// action has a click path (the page's context menu and the "…" menu of the selected page), a keyboard path (the "…"
// menu, and on a focused page ↩ rename, ⌥← ⌥→ move, ⌘⌫ remove) and VoiceOver actions (ARCHITECTURE §9.5).
// Selecting a page edits it and shows it on the stage. Right to left the pages run from the right: Move left / right
// and ⌥← ⌥→ go the way they point.
import CrannyCore
import Foundation
import SwiftUI

struct PageStrip: View {
    @Environment(\.layoutDirection) private var direction
    let editor: LayoutEditor
    @Binding var selection: PageID
    let apply: LayoutCommit
    @State private var renaming: PageID?
    @State private var draftTitle = ""

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(editor.pages) { page in
                    PageCapsule(page: page, isSelected: page.id == selection) { selection = page.id }
                        .contextMenu { menu(for: page) }
                        .help(page.id == .nook
                              ? Text("↩ rename · ⌥← ⌥→ move", bundle: .module,
                                     comment: "Settings ▸ Layout & Widgets: tooltip of the Home page with its keys (rename, move)")
                              : Text("↩ rename · ⌥← ⌥→ move · ⌘⌫ remove", bundle: .module,
                                     comment: "Settings ▸ Layout & Widgets: tooltip of a user page with its keys (rename, move, remove)"))
                        .onKeyPress(.return) {
                            startRenaming(page)
                            return .handled
                        }
                        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                            guard press.modifiers.contains(.option), let step = direction.step(for: press.key) else { return .ignored }
                            movePage(page, by: step)
                            return .handled
                        }
                        .onKeyPress(keys: [.delete, .deleteForward]) { press in
                            guard press.modifiers.contains(.command), page.id != .nook else { return .ignored }
                            removePage(page)
                            return .handled
                        }
                        .accessibilityActions { actions(for: page) }
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
                if let selected = editor.page(selection) {
                    Menu {
                        menu(for: selected)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text("Page actions", bundle: .module, comment: "Settings ▸ Layout & Widgets: menu button with the selected page's actions"))
                    .accessibilityLabel(Text("Actions for \(LayoutRows.title(of: selected))", bundle: .module,
                                             comment: "Settings ▸ Layout & Widgets: VoiceOver label of the page actions menu; the argument is the page name"))
                }
            }
        } label: {
            RowLabel(title: LayoutRows.pages.title,
                     footnote: String(localized: "Home and up to three pages of your own. Rename, move or remove a page from its menu (…).",
                                      bundle: .module, comment: "Settings ▸ Layout & Widgets: footnote of Pages; (…) is the page actions menu button"))
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
        Button { movePage(page, by: direction.step(physical: -1)) } label: { Self.moveLeftTitle }
            .disabled(!canMove(page, physical: -1))
        Button { movePage(page, by: direction.step(physical: 1)) } label: { Self.moveRightTitle }
            .disabled(!canMove(page, physical: 1))
        if page.id != .nook {
            Divider()
            Button(role: .destructive) { removePage(page) } label: { Self.removeTitle }
        }
    }

    /// The same actions for VoiceOver (Symbol stays in the menus: it is a choice, not an action).
    @ViewBuilder private func actions(for page: NookPage) -> some View {
        Button { startRenaming(page) } label: {
            Text("Rename…", bundle: .module, comment: "Settings ▸ Layout & Widgets: rename a page")
        }
        if canMove(page, physical: -1) {
            Button { movePage(page, by: direction.step(physical: -1)) } label: { Self.moveLeftTitle }
        }
        if canMove(page, physical: 1) {
            Button { movePage(page, by: direction.step(physical: 1)) } label: { Self.moveRightTitle }
        }
        if page.id != .nook {
            Button { removePage(page) } label: { Self.removeTitle }
        }
    }

    private static var moveLeftTitle: Text {
        Text("Move Left", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place left")
    }
    private static var moveRightTitle: Text {
        Text("Move Right", bundle: .module, comment: "Settings ▸ Layout & Widgets: move a widget or a page one place right")
    }
    private static var removeTitle: Text {
        Text("Remove Page", bundle: .module, comment: "Settings ▸ Layout & Widgets: removes a user page (its widgets stay available)")
    }

    /// Whether "Move Left" (`physical` −1) or "Move Right" (+1) has somewhere to go in this layout direction.
    private func canMove(_ page: NookPage, physical: Int) -> Bool {
        guard let index = editor.pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return editor.pages.indices.contains(index + direction.step(physical: physical))
    }

    private func movePage(_ page: NookPage, by offset: Int) {
        apply { $0.movePage(page.id, by: offset); return nil }
    }

    /// Removes a user page (Home stays); the selection falls back to Home.
    private func removePage(_ page: NookPage) {
        guard page.id != .nook else { return }
        if selection == page.id { selection = .nook }
        apply { $0.removePage(page.id); return nil }
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
    Form { PageStrip(editor: editor, selection: $selection, apply: .preview) }
        .formStyle(.grouped)
        .frame(width: 650, height: 140)
}
