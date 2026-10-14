// CrannyNotchUI/Nook/WidgetCard.swift — the card chrome around a widget's content (DESIGN.md §6.8): the
// smoked card (or flat), hover fill, the ⋯ overflow menu (on hover, ⌘. on a focused card, VoiceOver actions),
// the keyboard focus ring, a VoiceOver container named after the widget, and a placeholder for widgets whose
// module is not registered. Widgets draw content only (ARCHITECTURE.md §3.5). The widget's content is built only
// when what it draws changes: the hover and popover state live in the chrome (`CardHoverChrome`), so a pointer
// passing over a card redraws the chrome alone, and a card whose inputs are unchanged is skipped (`WidgetCard:
// Equatable`, used with `.equatable()`), so a grid update or a drag in the layout editor rebuilds no other widget.
import CrannyCore
import Foundation
import SwiftUI

/// What a card can ask the layout for (from its ⋯ menu or VoiceOver actions). The closures capture only references
/// that stay the same while the card is on screen (the scene, the registry, the owner's actions) and the page they
/// edit, and read the layout when they run; so a card keeps the set it was drawn with while nothing else changes.
struct CardCommands {
    /// The page these commands edit (nil: none). Part of a card's identity for redraws (`WidgetCard ==`): a card
    /// that shows another page gets that page's commands.
    var page: PageID?
    var remove: @MainActor (WidgetID) -> Void = { _ in }
    var resize: @MainActor (WidgetID, Int) -> Void = { _, _ in }
    var editLayout: @MainActor () -> Void = {}
    /// Widths the widget may take on this page (its sizes, limited by the room left).
    var allowedSizes: @MainActor (WidgetID) -> [Int] = { _ in [] }
}

struct WidgetCard: View {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
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
            .modifier(CardHoverChrome(id: item.widget, widget: widget, title: title, cells: cells, rows: rows,
                                      isEditing: isEditing, isFocused: isFocused, commands: commands))
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
                Image(systemName: placeholder.symbol).notchGlyph(.placeholder)
                Text(verbatim: placeholder.title).crannyFont(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.palette.tertiaryLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Redraws

extension WidgetCard: Equatable {
    /// Equal when the card draws the same: its item, rows, mode, focus, size clamping and registry, and commands for
    /// the same page. The command closures themselves are left out: every parent update builds new ones that do the
    /// same (`CardCommands`). The theme, the context and observed widget state still update a card as usual.
    static func == (a: WidgetCard, b: WidgetCard) -> Bool {
        a.item == b.item && a.registry === b.registry && a.rows == b.rows && a.isEditing == b.isEditing
            && a.isFocused == b.isFocused && a.clampsToSizes == b.clampsToSizes && a.commands.page == b.commands.page
    }
}

// MARK: - Chrome

/// Everything the card draws around the widget, with the state only it uses: hover, the options popover and the ⌘.
/// list. A modifier, so a change of that state re-evaluates the chrome, not the widget it wraps (`content`).
private struct CardHoverChrome: ViewModifier {
    @Environment(\.cranny) private var theme
    @Environment(\.notchContext) private var context
    @State private var hovered = false
    @State private var showsOptions = false
    @State private var showsKeyboardMenu = false
    let id: WidgetID
    let widget: AnyNookWidget?
    let title: String
    let cells: Int
    let rows: Int
    let isEditing: Bool
    let isFocused: Bool
    let commands: CardCommands

    func body(content: Content) -> some View {
        content
            .cardChrome(cells: cells, rows: rows, hovered: hovered && !isEditing, frameless: widget?.isFrameless ?? false)
            .overlay(alignment: .topTrailing) {
                if !isEditing {
                    // Always in the hierarchy (its NSMenu must survive the pointer leaving the card for the menu);
                    // visible on hover, while its ⌘. list is open, or with keyboard focus on the card.
                    let visible = hovered || showsKeyboardMenu || (isFocused && context.keyboardNavigation)
                    CardOverflowMenu(widget: id, hasOptions: widget?.hasOptions ?? false, cells: cells,
                                     commands: commands, showOptions: { showsOptions = true })
                        .popover(isPresented: $showsKeyboardMenu, arrowEdge: .bottom) {
                            CardActionsList(widget: id, hasOptions: widget?.hasOptions ?? false, cells: cells,
                                            commands: commands, showOptions: { showsKeyboardMenu = false; showsOptions = true },
                                            done: { showsKeyboardMenu = false })
                        }
                        .padding(Space.xs)
                        .opacity(visible ? 1 : 0)
                        .animation(theme.animation(.hover), value: visible)
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
            .accessibilityActions {
                CardAccessibilityActions(widget: id, hasOptions: widget?.hasOptions ?? false, cells: cells,
                                         isEditing: isEditing, commands: commands, showOptions: { showsOptions = true })
            }
    }
}

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
            .frame(minWidth: Self.minimumWidth)
    }

    /// A popover never narrower than a short form row.
    static let minimumWidth: CGFloat = 220
}

// MARK: - Placeholder

/// What a card shows for a widget no module registered (an ID left in a saved layout): its raw identifier and a
/// placeholder glyph. Previews and tests that want real names register Core's stand-ins
/// (`ModuleRegistry.addPreviewStandIns()`); the app registers every real widget.
struct WidgetPlaceholder {
    let title: String
    let symbol = "app.dashed"

    init(_ id: WidgetID) { title = id.rawValue }
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
