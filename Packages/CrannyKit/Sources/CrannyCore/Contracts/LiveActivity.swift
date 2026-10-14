// CrannyCore/Contracts/LiveActivity.swift
// Live activities: compact wings around the camera, the satellite, peek rows (DESIGN.md §9).
import SwiftUI

/// DESIGN.md §9.4. Lower raw value = more important. The user's order (Settings ▸ Live Activities)
/// only breaks ties *within* a class.
public nonisolated enum ActivityPriority: Int, Comparable, Codable, Sendable, CaseIterable {
    case hud = 0        // P0: transient, pre-empts everything for its lifetime
    case alert = 1      // P1: meeting soon, timer done, low battery, device connected, charging
    case ongoing = 2    // P2: meeting in progress, timer running, now playing
    case passive = 3    // P3: paused media
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Where the shell asks an activity to draw.
public nonisolated enum ActivityPlacement: Sendable, CaseIterable {
    case compactLeading     // left wing, content hugs the camera (trailing-aligned)
    case compactTrailing    // right wing, content hugs the camera (leading-aligned)
    case minimal            // 24u satellite circle: ONE glyph, ring or artwork
    case peekRow            // one 52-pt row: [visual 40] [title/subtitle] [≤ 3 controls]
}

/// Two-finger horizontal swipe over the compact/peek presentation of THIS activity (DESIGN.md §4.4).
public nonisolated enum ActivityGesture: Sendable, Equatable {
    case swipeLeft, swipeRight
}

/// Static description of an activity, shown in Settings ▸ Live Activities.
public nonisolated struct ActivityKind: Identifiable, Hashable, Sendable {
    public let id: ActivityID
    public let module: ModuleID
    public let title: String               // localized ("Now Playing")
    public let symbol: String
    public let defaultPriority: ActivityPriority
    public let isEnabledByDefault: Bool
    /// Whether "Peek on change" is offered for this kind, and its default.
    public let canPeekOnChange: Bool
    public let peeksOnChangeByDefault: Bool

    public init(id: ActivityID, module: ModuleID, title: String, symbol: String, defaultPriority: ActivityPriority,
                isEnabledByDefault: Bool = true, canPeekOnChange: Bool = false, peeksOnChangeByDefault: Bool = false) {
        self.id = id; self.module = module; self.title = title; self.symbol = symbol
        self.defaultPriority = defaultPriority; self.isEnabledByDefault = isEnabledByDefault
        self.canPeekOnChange = canPeekOnChange; self.peeksOnChangeByDefault = peeksOnChangeByDefault
    }
}

/// A one-shot visual played by CrannyNotchUI (CrannyEffects) on behalf of an activity (DESIGN.md §5.5).
/// Feature modules cannot import CrannyEffects, so they NAME the moment and the shell draws it.
public nonisolated enum DelightMoment: String, Sendable, Equatable, CaseIterable {
    case emberBurst     // timer done
    case chargeSweep    // charger connected: green sweep along the lower rim
    // Shell-driven (activities never return these):
    case songRipple     // track change while open: tide/aurora energy ripple
    case firstLight     // first open per session: light fills outward from the camera
    case gulp           // file caught: height −3 pt, spring back
}

/// A named action: VoiceOver custom action, keyboard/peek control, and the satellite/peek click targets.
public struct ActivityAction: Identifiable {
    public let id: String
    public let title: String               // localized ("Join meeting")
    public let symbol: String?
    public let perform: @MainActor () -> Void
    public init(id: String, title: String, symbol: String? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.symbol = symbol; self.perform = perform
    }
}

/// Implemented as an `@Observable final class` per activity (a module owns a FIXED set of them and
/// flips `isActive`). The shell observes the properties below; changing any of them re-arbitrates.
///
/// Rules (DESIGN.md §9.1–9.3): leading and trailing describe the SAME activity; one datum per side;
/// no free text in compact except tested `compactLabel` abbreviations; at most ONE interactive control
/// in compact (Join); peek rows have ≤ 3 controls with ≥ 28-pt hit targets.
@MainActor public protocol LiveActivity: AnyObject {
    associatedtype Leading: View
    associatedtype Trailing: View
    associatedtype Minimal: View
    associatedtype Row: View

    var id: ActivityID { get }
    /// Shown at all (still subject to user toggles, pause, dismissal and full-screen policy).
    var isActive: Bool { get }
    var priority: ActivityPriority { get }
    var slot: SlotWidth { get }
    /// Increment on every MEANINGFUL change (new track, last minute, meeting started, device connected).
    /// Undoes a swipe-up dismissal and, if the kind peeks on change (or priority is `.alert`), auto-peeks once.
    var revision: Int { get }
    /// Transient activities (charging 2.6 s, device connected, HUD 1.5 s) set this; the shell drops them after.
    var expiresAt: Date? { get }
    /// Light-layer palette while this is the top activity (`.timer`, `.charging`, album palette…).
    var palette: AmbientPalette? { get }
    /// Click on compact/peek opens the Nook focused on this widget.
    var opensWidget: WidgetID? { get }
    /// Floating-island displays only: optional label in the middle (`compactLabel`, ≤ 160 pt), e.g. track title.
    var middleLabel: String? { get }
    var accessibilityLabel: String { get }      // "Now playing: Midnight Window by The Example Band"
    var accessibilityValue: String? { get }     // "2 minutes 11 seconds left"
    var actions: [ActivityAction] { get }
    /// Played once by CrannyNotchUI when `revision` changes while this activity is visible (§5.5 caps apply).
    var delight: DelightMoment? { get }

    /// Return true if handled (Now Playing: next/previous track). Called on the main actor.
    func handle(_ gesture: ActivityGesture) -> Bool

    @ViewBuilder func compactLeading() -> Leading
    @ViewBuilder func compactTrailing() -> Trailing
    @ViewBuilder func minimal() -> Minimal
    @ViewBuilder func peekRow() -> Row
}

public extension LiveActivity {
    var expiresAt: Date? { nil }
    var palette: AmbientPalette? { nil }
    var opensWidget: WidgetID? { nil }
    var middleLabel: String? { nil }
    var accessibilityValue: String? { nil }
    var actions: [ActivityAction] { [] }
    var delight: DelightMoment? { nil }
    func handle(_ gesture: ActivityGesture) -> Bool { false }

    /// Type-erased view for a placement; callable on `any LiveActivity`.
    func view(for placement: ActivityPlacement) -> AnyView {
        switch placement {
        case .compactLeading: AnyView(compactLeading())
        case .compactTrailing: AnyView(compactTrailing())
        case .minimal: AnyView(minimal())
        case .peekRow: AnyView(peekRow())
        }
    }
}

/// What the registry stores for each activity.
public struct RegisteredActivity: Identifiable {
    public let kind: ActivityKind
    public let activity: any LiveActivity
    /// A self-contained instance with sample data (Settings "Simulate" chips, onboarding stage). Never
    /// touches the module's real model. nil = the kind cannot be simulated.
    public let makeSample: (@MainActor () -> any LiveActivity)?
    /// Extra rows under this activity in Settings ▸ Live Activities (module-owned keys, e.g. meeting lead time).
    public let makeOptions: (@MainActor () -> AnyView)?
    public var id: ActivityID { kind.id }
}
