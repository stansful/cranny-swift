// CrannyTray/UI/TrayTileRow.swift — the scrolling row of tiles on the Tray page (DESIGN.md §8.1) and its keyboard
// map (§16): ← → move, ⇧ extends, ⌘A all, Space Quick Look, ↩ open, ⌘C copy, ⌘⌫ remove, ⌥⌘⌫ clear; also ⌘. stops
// running pipelines (the selection's, else all) and ⌘⌫ with nothing selected hides the error tiles of failed drops,
// which cannot be selected. The focus ring appears only after a key press in the row. Lists never stagger on open
// (§4.5); inserts use `listReorder`.
import AppKit
import CrannyCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TrayTileRow: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    let store: TrayStore
    var isInteractive = true
    @FocusState private var focused: Bool
    @State private var usedKeyboard = false

    var body: some View {
        ScrollViewReader { proxy in
            TrayScrollRow {
                HStack(spacing: Space.m) {
                    ForEach(store.jobs.filter { $0.sourceIDs.isEmpty }) { job in
                        TrayJobTile(job: job, store: store)
                            .transition(.opacity)
                    }
                    ForEach(store.items) { item in
                        TrayTile(item: item, store: store, isFocused: focused && usedKeyboard && store.selection.cursor == item.id,
                                 isInteractive: isInteractive) {
                            // The panel becomes key (without activating Cranny) so the Tray's keys work, but only
                            // for the selection: it still closes when the pointer leaves (TrayStore.takeSelectionFocus).
                            store.takeSelectionFocus()
                            usedKeyboard = false
                            focused = true
                        }
                            .id(item.id)
                            .transition(.opacity.combined(with: .scale(scale: theme.reduceMotion ? 1 : 0.9)))
                    }
                }
                .animation(theme.animation(.listReorder), value: store.order)
                .animation(theme.animation(.listReorder), value: store.jobs.map(\.id))
            }
            .frame(height: TrayTileLayout(theme: theme).height)
            .onChange(of: store.selection.cursor) { _, cursor in
                guard let cursor else { return }
                withAnimation(theme.animation(.listReorder)) { proxy.scrollTo(cursor) }
            }
        }
        .focusable(isInteractive)
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handle(press) }
        .onCommand(#selector(NSResponder.selectAll(_:))) { usedKeyboard = true; store.selectAll() }   // Edit ▸ Select All (⌘A)
        .onCopyCommand {
            let urls = store.urls(of: store.selectedItems)
            return urls.map { NSItemProvider(object: $0 as NSURL) }
        }
        .onAppear { if context.openReason == .keyboard { focused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Files", bundle: .module, comment: "Tray page: VoiceOver label of the row of files; also the Files widget's name"))
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        switch press.key {
        case .leftArrow, .rightArrow:
            usedKeyboard = true
            store.moveSelection(forward: press.key == .rightArrow, extend: press.modifiers.contains(.shift))
        case .space:
            store.toggleQuickLook(store.selection.cursor)
        case .return:
            store.open()
        case .delete where command && press.modifiers.contains(.option):
            store.clear()
        case .delete where command:
            if store.selection.isEmpty { store.dismissFailedJobs() } else { store.removeTargets() }
        default:
            if command, press.characters.lowercased() == "a" { usedKeyboard = true; store.selectAll(); return .handled }
            if command, press.characters == ".", !store.stoppableJobs().isEmpty { store.stopRunning(); return .handled }
            return .ignored
        }
        return .handled
    }
}

/// A run on dropped files that are not in the Tray: the pipeline's glyph, a ring, then the result (or the error).
struct TrayJobTile: View {
    @Environment(\.cranny) private var theme
    let job: TrayJob
    let store: TrayStore
    @State private var hovered = false

    var body: some View {
        let p = theme.palette
        let layout = TrayTileLayout(theme: theme)
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.grid.innerRadius, style: .continuous).fill(p.control)
                if job.failure == nil {
                    TrayProgressRing(progress: job.progress)
                } else {
                    Image(systemName: "doc").font(.system(size: TrayMetrics.thumbnail * 0.4)).foregroundStyle(p.tertiaryLabel)
                }
            }
            .frame(width: TrayMetrics.thumbnail, height: TrayMetrics.thumbnail)
            .overlay(alignment: .topTrailing) {
                if job.failure != nil { TrayErrorBadge().offset(x: Space.xs, y: -Space.xs) }
            }
            Text(verbatim: job.placeholderName ?? job.title)
                .crannyFont(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(p.secondaryLabel)
                .frame(width: layout.width - Space.xs, height: layout.captionHeight)
        }
        .padding(.top, Space.xs)
        .frame(width: layout.width, height: layout.height, alignment: .top)
        .overlay(alignment: .topLeading) {
            if hovered {
                TrayRoundButton(symbol: "xmark", label: job.failure == nil ? TrayItemCommand.stopTitle : TrayItemCommand.dismissTitle) {
                    if job.failure == nil { store.cancel(job.id) } else { store.dismissJob(job.id) }
                }
                .offset(x: -Space.xxs, y: -Space.xxs)
            }
        }
        .onHover { hovered = $0 }
        .help(job.failure ?? job.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: job.placeholderName ?? job.title))
        .accessibilityValue(Text(verbatim: TrayTileAccessibility.value(selected: false, job: job.failure == nil ? job : nil,
                                                                       failure: job.failure)))
        .accessibilityAction(named: Text(verbatim: job.failure == nil ? TrayItemCommand.stopTitle : TrayItemCommand.dismissTitle)) {
            if job.failure == nil { store.cancel(job.id) } else { store.dismissJob(job.id) }
        }
    }
}

#Preview("Tile row") {
    TrayTileRow(store: TrayPreview.store(items: 8, selected: 2), isInteractive: false)
        .frame(width: NookGrid().width(cells: 8) - 2 * NookGrid().density.cardPadding)
        .padding(Space.l)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
