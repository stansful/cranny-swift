// CrannyNotchUI/NotchScene.swift — the render model of one notch (one per display panel, one per stage).
import CrannyCore
import CrannyEffects
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// What the open Nook is showing.
public nonisolated enum NookMode: Equatable, Sendable {
    case grid
    case palette                       // ⌘K
    case editLayout                    // ⌘E
    case focus(WidgetID)               // Notes focus: all columns × 3 rows
    case catchFiles([UTType])          // file drag in progress (DESIGN.md §8.3)
}

public nonisolated struct OpenState: Equatable, Sendable {
    public var page: PageID
    public var focus: WidgetID?
    public var mode: NookMode
    public var reason: OpenReason
    public init(page: PageID, focus: WidgetID? = nil, mode: NookMode = .grid, reason: OpenReason) {
        self.page = page; self.focus = focus; self.mode = mode; self.reason = reason
    }
}

/// Written ONLY by its owner (the shell's per-display view model, or a preview stage). Views read it.
@MainActor @Observable public final class NotchSceneModel {
    public var phase: NotchPhase = .idle
    public var layout: NotchLayout
    public var theme: CrannyTheme
    public var primary: ActivityID?
    public var satellite: ActivityID?
    public var peekRows: [ActivityID] = []
    /// Stages (Settings preview, onboarding) put `RegisteredActivity.makeSample()` instances here; the canvas
    /// prefers them over the registry's live objects. The shell leaves it empty.
    public var sampleActivities: [ActivityID: any LiveActivity] = [:]
    public var open: OpenState?
    public var pinned = false
    public var ambient: AmbientPalette = .afterglow
    /// One-shot delight to play (DESIGN.md §5.5). The owner applies the caps (one at a time, not paused,
    /// not in full screen, not under Calm/Instant/Reduce Motion) and bumps `delightSerial`; NotchUI plays
    /// each serial once. Sources: activities' `delight`, track change (`.songRipple`), first open (`.firstLight`),
    /// file caught (`.gulp`).
    public var delight: DelightMoment?
    public var delightSerial = 0
    /// Live rubber-band offset from a gesture in progress (pt; +y = down).
    public var gestureTranslation: CGSize = .zero
    public var context = NotchContext()
    public let zones: NotchZones

    public init(layout: NotchLayout, theme: CrannyTheme, zones: NotchZones = NotchZones()) {
        self.layout = layout; self.theme = theme; self.zones = zones
    }

    /// The shape for the current state (pure function of the model + layout, DESIGN.md §3.3).
    public var geometry: NotchGeometry {
        switch phase {
        case .hidden: .zero
        case .idle: layout.closed
        case .breath: layout.hover
        case .compact: layout.compact(primarySlot)
        case .peek: layout.peek(rows: max(peekRows.count, 1))
        case .open:
            if case .focus? = open?.mode { layout.open(columns: layout.maxColumns, rows: 3) }
            else { layout.open(columns: openColumns) }
        }
    }
    /// Set by the owner from the registry (slot of the primary activity).
    public var primarySlot: SlotWidth = .short
    /// Sum of visible widget widths on the current page (set by the owner).
    public var openColumns: Int = 10
}

/// Callbacks from the views to the owner. Stages pass no-ops.
public struct NotchUIActions {
    public var selectPage: @MainActor (PageID) -> Void = { _ in }
    public var togglePin: @MainActor () -> Void = {}
    public var showPalette: @MainActor () -> Void = {}
    public var openSettings: @MainActor () -> Void = {}
    public var close: @MainActor () -> Void = {}
    public var activityTapped: @MainActor (ActivityID) -> Void = { _ in }
    public var satelliteTapped: @MainActor () -> Void = {}
    public var commitLayout: @MainActor ([NookPage]) -> Void = { _ in }
    /// ⌘K / ⌘E / Esc chain / focus mode: NotchUI asks, the owner writes `open.mode`.
    public var setMode: @MainActor (NookMode) -> Void = { _ in }
    /// Keyboard focus moved to a widget (nil = none); the owner mirrors it into `context.focusedWidget`.
    public var focusWidget: @MainActor (WidgetID?) -> Void = { _ in }
    /// VoiceOver "Dismiss" action and swipe-up on the satellite.
    public var dismissActivity: @MainActor (ActivityID) -> Void = { _ in }
    /// VoiceOver "Open" on the collapsed notch.
    public var open: @MainActor () -> Void = {}
    public init() {}
}
