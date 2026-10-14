// CrannyCore/Contracts/Widget.swift
// A Nook widget: content for a card of N cells × 2 rows (DESIGN.md §6.3, §6.7, §6.8).
import SwiftUI

/// Allowed widths in grid cells (DESIGN.md §6.7). Height is always the grid height (2 rows; 3 in Notes focus).
public nonisolated struct WidgetSizes: Equatable, Sendable {
    /// The narrowest the widget can be.
    public let minimum: Int
    /// The width it gets when added.
    public let preferred: Int
    /// The widest it can be.
    public let maximum: Int
    /// Sizes with 1 ≤ minimum ≤ preferred ≤ maximum (anything else is a programmer error).
    public init(minimum: Int, preferred: Int, maximum: Int) {
        precondition(1 <= minimum && minimum <= preferred && preferred <= maximum, "invalid widget sizes")
        self.minimum = minimum; self.preferred = preferred; self.maximum = maximum
    }
    /// `cells` within these sizes.
    public func clamp(_ cells: Int) -> Int { min(max(cells, minimum), maximum) }
}

/// Everything a widget needs to lay itself out. Value type: cheap to diff, safe to pass around.
public nonisolated struct WidgetContext: Equatable, Sendable {
    /// Width in grid cells (already clamped to `sizes`).
    public var cells: Int
    /// 2, or 3 while the Nook is in a focus mode.
    public var rows: Int
    /// Size of the content area (card size minus card padding; the full card for frameless widgets).
    public var contentSize: CGSize
    /// The user is editing the layout (⌘E): show no live content that would fight the drag.
    public var isEditingLayout: Bool
    /// Keyboard focus is inside this widget, or it is the focused widget of a focus mode.
    public var isFocused: Bool
    /// Rendered on a Settings/onboarding stage or in `#Preview`: never start hardware (camera, audio tap),
    /// never prompt for permissions, never write user data. Sample data is allowed.
    public var isPreview: Bool
    /// Demo mode with redaction: replace personal text (event titles, note text) with neutral placeholders.
    public var redactsPersonalData: Bool

    /// A context; everything but the size defaults to an ordinary open Nook.
    public init(cells: Int, rows: Int = 2, contentSize: CGSize, isEditingLayout: Bool = false,
                isFocused: Bool = false, isPreview: Bool = false, redactsPersonalData: Bool = false) {
        self.cells = cells; self.rows = rows; self.contentSize = contentSize
        self.isEditingLayout = isEditingLayout; self.isFocused = isFocused
        self.isPreview = isPreview; self.redactsPersonalData = redactsPersonalData
    }
}

/// Implemented by feature modules (usually an `@Observable final class` holding its model).
/// The shell wraps `makeBody` in the card chrome (`crannyCard`, hover, overflow menu, focus section,
/// VoiceOver container labelled `title`) — widgets draw content only, never their own card.
@MainActor public protocol NookWidget: AnyObject {
    /// The widget's content view.
    associatedtype Content: View
    /// The options popover's view (`EmptyView` = no options).
    associatedtype Options: View = EmptyView

    /// The widget's identifier (persisted in layouts).
    var id: WidgetID { get }
    /// Localized, sentence case ("To-dos"). Also the VoiceOver container label.
    var title: String { get }
    /// SF Symbol for the widget library and collapsed tabs (DESIGN.md §14.1 list only).
    var symbol: String { get }
    /// One localized line for the widget library.
    var summary: String { get }
    /// Allowed widths in cells.
    var sizes: WidgetSizes { get }
    /// `true` for widgets whose content IS the card (Mirror preview): no padding, no smoked fill.
    var isFrameless: Bool { get }

    /// The content for `context` (the shell draws the card around it).
    @ViewBuilder func makeBody(context: WidgetContext) -> Content
    /// Per-widget options shown in a popover (Settings ▸ Layout & Widgets and the card's ⋯ menu).
    @ViewBuilder func makeOptions() -> Options
}

public extension NookWidget {
    var isFrameless: Bool { false }
}

public extension NookWidget where Options == EmptyView {
    func makeOptions() -> EmptyView { EmptyView() }
}

/// Type-erased widget stored by the registry.
@MainActor public final class AnyNookWidget: Identifiable {
    public let base: any NookWidget
    /// The widget's identifier.
    public var id: WidgetID { base.id }
    /// Localized title (VoiceOver container label, widget library).
    public var title: String { base.title }
    /// Library and collapsed-tab glyph.
    public var symbol: String { base.symbol }
    /// One localized line for the widget library.
    public var summary: String { base.summary }
    /// Allowed widths in cells.
    public var sizes: WidgetSizes { base.sizes }
    /// The content is the card (no padding, no smoked fill).
    public var isFrameless: Bool { base.isFrameless }
    /// The widget has options (`makeOptions()` is not `EmptyView`): the card shows them in its ⋯ menu.
    public let hasOptions: Bool
    private let body: @MainActor (WidgetContext) -> AnyView
    private let options: @MainActor () -> AnyView

    /// Wraps `widget` (the registry does this in `add(widget:)`).
    public init<W: NookWidget>(_ widget: W) {
        base = widget
        hasOptions = W.Options.self != EmptyView.self
        body = { AnyView(widget.makeBody(context: $0)) }
        options = { AnyView(widget.makeOptions()) }
    }
    /// The widget's content for `context`.
    public func makeBody(context: WidgetContext) -> AnyView { body(context) }
    /// The widget's options view.
    public func makeOptions() -> AnyView { options() }
}

/// A full-width page in the Nook header provided by a module (the Tray page).
/// The Nook grid page and user pages are owned by the shell (`CoreSettings.pages`).
public struct PageDescriptor: Identifiable {
    /// The page's identifier (the header tab, `NotchControl.open(page:)`).
    public let id: PageID
    /// The tab title, localized.
    public let title: String
    /// The tab glyph.
    public let symbol: String
    /// Sort key among module pages (the grid page "nook" always comes first).
    public let order: Int
    /// `micro` count badge in the header ("3"), nil = none. Read inside SwiftUI bodies (observable).
    public let badge: @MainActor () -> Int?
    /// Builds the page for the open Nook (full width).
    public let makeView: @MainActor (WidgetContext) -> AnyView

    /// A page; no badge by default.
    public init(id: PageID, title: String, symbol: String, order: Int,
                badge: @escaping @MainActor () -> Int? = { nil },
                makeView: @escaping @MainActor (WidgetContext) -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.order = order
        self.badge = badge; self.makeView = makeView
    }
}
