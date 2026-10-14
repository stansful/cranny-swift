// CrannyTray/UI/TrayTileRow.swift — the scrolling row of tiles on the Tray page (DESIGN.md §8.1) and its keyboard
// map (§16): ← → move, ⇧ extends, ⌘A all, Space Quick Look, ↩ open, ⌘C copy, ⌘⌫ remove, ⌥⌘⌫ clear. The focus ring
// appears only after a key press in the row. Lists never stagger on open (§4.5); inserts use `listReorder`.
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
                            // Like clicking a text field: the panel becomes key (without activating Cranny), so the
                            // Tray's keys work; it hands focus back when Cranny closes (ARCHITECTURE.md §4.10).
                            store.notch.requestKeyboardFocus()
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
            .frame(height: TrayMetrics.tileHeight)
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
            store.removeTargets()
        default:
            if command, press.characters.lowercased() == "a" { usedKeyboard = true; store.selectAll(); return .handled }
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
        VStack(spacing: Space.xs) {
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
                .frame(width: TrayMetrics.tileWidth - Space.xs)
        }
        .padding(.top, Space.xs)
        .frame(width: TrayMetrics.tileWidth, height: TrayMetrics.tileHeight, alignment: .top)
        .overlay(alignment: .topLeading) {
            if hovered {
                TrayRoundButton(symbol: "xmark", label: job.failure == nil
                    ? String(localized: "Stop", bundle: .module, comment: "Tray tile: cancel a running pipeline (VoiceOver label, tooltip)")
                    : String(localized: "Dismiss", bundle: .module, comment: "Tray tile: hide a failed run of dropped files")) {
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
        .accessibilityAction(named: Text(verbatim: job.failure == nil
            ? String(localized: "Stop", bundle: .module, comment: "Tray tile: cancel a running pipeline (VoiceOver label, tooltip)")
            : String(localized: "Dismiss", bundle: .module, comment: "Tray tile: hide a failed run of dropped files"))) {
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
