// CrannyNotchUI/Nook/WidgetCard.swift — the card chrome around a widget's content (DESIGN.md §6.8): the
// smoked card (or flat), hover fill, the ⋯ overflow menu (on hover, ⌘. on a focused card, VoiceOver actions),
// the keyboard focus ring, a VoiceOver container named after the widget, and a placeholder for widgets whose
// module is not registered. Widgets draw content only (ARCHITECTURE.md §3.5).
import CrannyCore
import Foundation
import SwiftUI

/// What a card can ask the layout for (from its ⋯ menu or VoiceOver actions).
struct CardCommands {
    var remove: @MainActor (WidgetID) -> Void = { _ in }
    var resize: @MainActor (WidgetID, Int) -> Void = { _, _ in }
    var editLayout: @MainActor () -> Void = {}
    /// Widths the widget may take on this page (its sizes, limited by the room left).
    var allowedSizes: @MainActor (WidgetID) -> [Int] = { _ in [] }
}

struct WidgetCard: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    @State private var hovered = false
    @State private var showsOptions = false
    @State private var showsKeyboardMenu = false
    let item: NookItem
    let registry: ModuleRegistry
    var rows: Int = 2
    var isEditing = false
    var isFocused = false
    var commands = CardCommands()
    /// Notes focus spans all columns, beyond the widget's own maximum width.
    var clampsToSizes = true

    var body: some View {
        let widget = registry.widget(item.widget)
        let cells = clampsToSizes ? (widget?.sizes.clamp(item.cells) ?? max(item.cells, 1)) : max(item.cells, 1)
        let title = widget?.title ?? WidgetPlaceholder(item.widget).title
        content(widget: widget, cells: cells)
            .allowsHitTesting(!isEditing)
            .cardChrome(cells: cells, rows: rows, hovered: hovered && !isEditing, frameless: widget?.isFrameless ?? false)
            .overlay(alignment: .topTrailing) {
                if !isEditing && (hovered || showsKeyboardMenu) {
                    CardOverflowMenu(widget: item.widget, hasOptions: widget?.hasOptions ?? false, cells: cells,
                                     commands: commands, showOptions: { showsOptions = true })
                        .popover(isPresented: $showsKeyboardMenu, arrowEdge: .bottom) {
                            CardActionsList(widget: item.widget, hasOptions: widget?.hasOptions ?? false, cells: cells,
                                            commands: commands, showOptions: { showsKeyboardMenu = false; showsOptions = true },
                                            done: { showsKeyboardMenu = false })
                        }
                        .padding(Space.xs)
                        .transition(.opacity.animation(theme.animation(.hover)))
                }
            }
            .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                if let widget { WidgetOptionsPopover(widget: widget) }
            }
            .crannyFocusRing(isFocused && (context.keyboardNavigation || context.openReason == .keyboard),
                             radius: theme.grid.cardRadius)
            .onHover { hovered = $0 }
            .background {
                // ⌘. on the focused card opens its actions (the ⋯ menu cannot be opened from the keyboard).
                if isFocused {
                    Button { showsKeyboardMenu = true } label: { EmptyView() }
                        .keyboardShortcut(".", modifiers: .command)
                        .buttonStyle(.plain).opacity(0).accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityActions { CardAccessibilityActions(widget: item.widget, hasOptions: widget?.hasOptions ?? false,
                                                             commands: commands, showOptions: { showsOptions = true }) }
    }

    @ViewBuilder private func content(widget: AnyNookWidget?, cells: Int) -> some View {
        let grid = theme.grid
        if let widget {
            let inset = widget.isFrameless ? 0 : grid.density.cardPadding
            widget.makeBody(context: WidgetContext(
                cells: cells, rows: rows,
                contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset,
                                    height: CardChrome.height(rows: rows, grid: grid) - 2 * inset),
                isEditingLayout: isEditing, isFocused: isFocused || context.focusedWidget == widget.id,
                isPreview: context.isPreview, redactsPersonalData: context.redactsPersonalData))
        } else {
            let placeholder = WidgetPlaceholder(item.widget)
            VStack(spacing: Space.s) {
                Image(systemName: placeholder.symbol).font(.system(size: 20, weight: .medium))
                Text(verbatim: placeholder.title).crannyFont(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.palette.tertiaryLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Chrome

/// `crannyCard` for any number of rows: Core's card modifier is 2 rows tall; Notes focus needs 3.
struct CardChrome: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let cells: Int
    let rows: Int
    let hovered: Bool
    let frameless: Bool

    static func height(rows: Int, grid: NookGrid) -> CGFloat {
        var g = grid
        g.rows = rows
        return g.height
    }

    func body(content: Content) -> some View {
        if rows == 2 {
            content.crannyCard(cells: cells, hovered: hovered, frameless: frameless)
        } else {
            let g = theme.grid, p = theme.palette
            let shape = RoundedRectangle(cornerRadius: g.cardRadius, style: .continuous)
            let carded = theme.widgetStyle == .cards && !frameless
            content
                .padding(frameless ? 0 : g.density.cardPadding)
                .frame(width: g.width(cells: cells), height: Self.height(rows: rows, grid: g), alignment: .topLeading)
                .background { if carded { shape.fill(hovered ? p.cardHover : p.card) } }
                .overlay {
                    if carded {
                        shape.strokeBorder(p.hairline, lineWidth: theme.increaseContrast ? 1 : StrokeWidth.hairline(displayScale))
                    }
                }
                .clipShape(shape)
                .containerShape(shape)
                .animation(theme.animation(.hover), value: hovered)
        }
    }
}

extension View {
    func cardChrome(cells: Int, rows: Int, hovered: Bool, frameless: Bool) -> some View {
        modifier(CardChrome(cells: cells, rows: rows, hovered: hovered, frameless: frameless))
    }
}

/// The widget's options in a popover (the same view as Settings ▸ Layout & Widgets).
private struct WidgetOptionsPopover: View {
    let widget: AnyNookWidget
    var body: some View {
        widget.makeOptions()
            .padding(Space.l)
            .frame(minWidth: 220)
    }
}

// MARK: - Placeholder

/// Name and glyph of a well-known widget, shown until its module registers it (DESIGN.md §14.1 symbols).
struct WidgetPlaceholder {
    let title: String
    let symbol: String

    init(_ id: WidgetID) {
        switch id {
        case .media: (title, symbol) = (String(localized: "Media", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "music.note")
        case .calendar: (title, symbol) = (String(localized: "Calendar", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "calendar")
        case .quickApps: (title, symbol) = (String(localized: "Quick Apps", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "app.dashed")
        case .mirror: (title, symbol) = (String(localized: "Mirror", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "web.camera")
        case .notes: (title, symbol) = (String(localized: "Notes", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "note.text")
        case .todos: (title, symbol) = (String(localized: "To-dos", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "checklist")
        case .timer: (title, symbol) = (String(localized: "Timer", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "timer")
        case .airDrop: (title, symbol) = ("AirDrop", "dot.radiowaves.up.forward")
        case .files: (title, symbol) = (String(localized: "Files", bundle: .module, comment: "Open panel: placeholder card for a widget whose module is not built yet"), "folder")
        default: (title, symbol) = (id.rawValue, "app.dashed")
        }
    }
}

#Preview("Cards · placeholders, hover menu") {
    let (_, registry) = previewScene(.open)
    HStack(spacing: Space.m) {
        WidgetCard(item: NookItem(.media, cells: 4), registry: registry)
        WidgetCard(item: NookItem(.timer, cells: 2), registry: registry, isFocused: true)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
