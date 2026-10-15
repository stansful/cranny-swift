// CrannyCore/Contracts/NotchContext.swift
// Read-only facts about the notch a view is rendered in. Set by CrannyNotchUI at the canvas root. What changes with
// a key press (keyboard focus, hold-⌘ hints, keyboard navigation) and the panel's visibility are environment entries
// of their own, beside `NotchContext`: a view is re-evaluated only when a fact it reads changes.
import SwiftUI

/// The visible presentation (DESIGN.md §3.3, ARCHITECTURE.md §4).
public nonisolated enum NotchPhase: String, Sendable, Codable {
    case hidden     // nothing drawn (full-screen policy, excluded app, locked, idle-hidden handle)
    case idle       // closed: exactly the hardware cutout, or the handle on displays without a notch
    case breath     // hover dwell acknowledged (+12u wide, +3u tall), nothing open yet
    case compact    // a live activity in the wings (+ optional satellite)
    case peek       // compact row + 52-pt rows below
    case open       // the Nook
}

/// Why the Nook opened (`NotchEvent.opened`, focus and type-to-capture rules).
public nonisolated enum OpenReason: String, Sendable, Codable {
    case hover, click, keyboard, swipe, drag, activity, programmatic, tutorial
}

/// The facts a notch view may depend on that change with the presentation (open, close, page, display), in the
/// environment (`@Environment(\.notchContext)`, or one field: `@Environment(\.notchContext.isPreview)`). Keyboard
/// focus, hold-⌘ hints and keyboard navigation change with every key press, so they are entries of their own
/// (`notchFocusedWidget`, `notchShowsCommandHints`, `notchKeyboardNavigation`).
public nonisolated struct NotchContext: Equatable, Sendable {
    /// The visible presentation.
    public var phase: NotchPhase = .idle
    /// Geometry of this display's notch and grid.
    public var layout: NotchLayout = NotchLayout(metrics: .reference)
    /// The display the canvas is on (nil on stages and in previews).
    public var display: DisplayKey?
    /// Why the Nook opened, while it is open.
    public var openReason: OpenReason?
    /// The page shown while open.
    public var page: PageID?
    /// Settings preview stage, onboarding stage or `#Preview`: no side effects.
    public var isPreview = false
    /// Demo mode with "Redact calendar titles".
    public var redactsPersonalData = false
    /// Closed, reference layout, no display.
    public init() {}
}

/// Named coordinate space of the fixed canvas (top-left origin). Zones report frames in it.
public nonisolated enum NotchCoordinateSpace {
    /// The coordinate space's name (`.named(NotchCoordinateSpace.name)`).
    public static let name = "cranny.canvas"
}

public extension EnvironmentValues {
    /// The notch's facts that change with its presentation (`NotchContext`).
    @Entry var notchContext = NotchContext()
    /// The widget that has keyboard focus or is in a focus mode.
    @Entry var notchFocusedWidget: WidgetID? = nil
    /// Hold-⌘ hints are visible: show `KeyCap`s next to commands.
    @Entry var notchShowsCommandHints = false
    /// The last interaction was the keyboard: draw `crannyFocusRing`s.
    @Entry var notchKeyboardNavigation = false
    /// The notch is on screen and not occluded: effects pause while it is not (`EffectBudget`, ARCHITECTURE.md §9.2).
    @Entry var notchIsOnScreen = true
    /// Namespace for matched geometry between compact, peek and widget presentations (`MatchedID`).
    @Entry var notchNamespace: Namespace.ID? = nil
    /// Drop / scroll zones of the canvas this view is in. nil on stages that do not take input.
    @Entry var notchZones: NotchZones? = nil
}

public extension View {
    /// `matchedGeometryEffect` in the canvas namespace; a no-op outside a notch canvas.
    func notchMatched(_ id: String, isSource: Bool = true) -> some View {
        modifier(NotchMatchedModifier(id: id, isSource: isSource))
    }
}

struct NotchMatchedModifier: ViewModifier {
    @Environment(\.notchNamespace) private var namespace
    let id: String
    let isSource: Bool
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}
