// CrannyCore/Contracts/NotchContext.swift
// Read-only facts about the notch a view is rendered in. Set by CrannyNotchUI at the canvas root.
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

public nonisolated enum OpenReason: String, Sendable, Codable {
    case hover, click, keyboard, swipe, drag, activity, programmatic, tutorial
}

public nonisolated struct NotchContext: Equatable, Sendable {
    public var phase: NotchPhase = .idle
    public var layout: NotchLayout = NotchLayout(metrics: .reference)
    public var display: DisplayKey?
    public var openReason: OpenReason?
    public var page: PageID?
    public var focusedWidget: WidgetID?
    /// Settings preview stage, onboarding stage or `#Preview`: no side effects.
    public var isPreview = false
    /// Demo mode with "Redact calendar titles".
    public var redactsPersonalData = false
    /// Hold-⌘ hints are visible: show `KeyCap`s next to commands.
    public var showsCommandHints = false
    /// The last interaction was the keyboard: draw `crannyFocusRing`s.
    public var keyboardNavigation = false
    public init() {}
}

/// Named coordinate space of the fixed canvas (top-left origin). Zones report frames in it.
public nonisolated enum NotchCoordinateSpace {
    public static let name = "cranny.canvas"
}

public extension EnvironmentValues {
    @Entry var notchContext = NotchContext()
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
