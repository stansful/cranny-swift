// CrannyCore/Contracts/Widget.swift
// A Nook widget: content for a card of N cells × 2 rows (DESIGN.md §6.3, §6.7, §6.8).
import SwiftUI

/// Allowed widths in grid cells (DESIGN.md §6.7). Height is always the grid height (2 rows; 3 in Notes focus).
public nonisolated struct WidgetSizes: Equatable, Sendable {
    public let minimum: Int
    public let preferred: Int
    public let maximum: Int
    public init(minimum: Int, preferred: Int, maximum: Int) {
        precondition(1 <= minimum && minimum <= preferred && preferred <= maximum, "invalid widget sizes")
        self.minimum = minimum; self.preferred = preferred; self.maximum = maximum
    }
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
    associatedtype Content: View
    associatedtype Options: View = EmptyView

    var id: WidgetID { get }
    /// Localized, sentence case ("To-dos"). Also the VoiceOver container label.
    var title: String { get }
    /// SF Symbol for the widget library and collapsed tabs (DESIGN.md §14.1 list only).
    var symbol: String { get }
    /// One localized line for the widget library.
    var summary: String { get }
    var sizes: WidgetSizes { get }
    /// `true` for widgets whose content IS the card (Mirror preview): no padding, no smoked fill.
    var isFrameless: Bool { get }

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
    public var id: WidgetID { base.id }
    public var title: String { base.title }
    public var symbol: String { base.symbol }
    public var summary: String { base.summary }
    public var sizes: WidgetSizes { base.sizes }
    public var isFrameless: Bool { base.isFrameless }
    public let hasOptions: Bool
    private let body: @MainActor (WidgetContext) -> AnyView
    private let options: @MainActor () -> AnyView

    public init<W: NookWidget>(_ widget: W) {
        base = widget
        hasOptions = W.Options.self != EmptyView.self
        body = { AnyView(widget.makeBody(context: $0)) }
        options = { AnyView(widget.makeOptions()) }
    }
    public func makeBody(context: WidgetContext) -> AnyView { body(context) }
    public func makeOptions() -> AnyView { options() }
}

/// A full-width page in the Nook header provided by a module (the Tray page).
/// The Nook grid page and user pages are owned by the shell (`CoreSettings.pages`).
public struct PageDescriptor: Identifiable {
    public let id: PageID
    public let title: String
    public let symbol: String
    /// Sort key among module pages (the grid page "nook" always comes first).
    public let order: Int
    /// `micro` count badge in the header ("3"), nil = none. Read inside SwiftUI bodies (observable).
    public let badge: @MainActor () -> Int?
    public let makeView: @MainActor (WidgetContext) -> AnyView

    public init(id: PageID, title: String, symbol: String, order: Int,
                badge: @escaping @MainActor () -> Int? = { nil },
                makeView: @escaping @MainActor (WidgetContext) -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.order = order
        self.badge = badge; self.makeView = makeView
    }
}
