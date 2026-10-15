// CrannyNotchUI/NotchScene.swift — the render model of one notch (one per display panel, one per stage).
// The contract of ARCHITECTURE.md §4.12. Additive since the foundation: `middleLabelWidth` (open issue 3),
// `isVisibleOnScreen`, `OpenState.gestureVelocity` and `headerActivity` (with `OpenHeaderActivity`). Keyboard focus,
// hold-⌘ hints and keyboard navigation moved out of `context` into properties of their own (energy pass).
import CrannyCore
import CrannyEffects
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// What the open Nook is showing.
public nonisolated enum NookMode: Equatable, Sendable {
    /// The page's widgets (or a module page such as the Tray).
    case grid
    /// The ⌘K command palette, in place of the grid at the same height.
    case palette                       // ⌘K
    /// Editing the page's layout (⌘E): drag to reorder, drag the handle to resize.
    case editLayout                    // ⌘E
    /// One widget at all columns × 3 rows (Notes focus).
    case focus(WidgetID)               // Notes focus: all columns × 3 rows
    /// A file drag is in progress: the catch zones (DESIGN.md §8.3).
    case catchFiles([UTType])          // file drag in progress (DESIGN.md §8.3)
}

/// The open presentation: which page, which widget has focus, what the panel is showing and why it opened.
public nonisolated struct OpenState: Equatable, Sendable {
    /// The selected page (`.nook` = Home, `.tray`, or a user page).
    public var page: PageID
    /// The widget to focus and highlight (click on an activity, `NotchControl.open(focus:)`).
    public var focus: WidgetID?
    /// Grid, palette, edit layout, focus mode or catch.
    public var mode: NookMode
    /// What opened the panel (keyboard opens show the focus ring at once).
    public var reason: OpenReason
    /// The fingers' speed (pt/s, downward) when a two-finger swipe opened the panel, else 0. The open spring starts
    /// with it, so the shape keeps moving with the fingers instead of starting from rest (DESIGN.md §4.4); Reduce
    /// Motion and Instant ignore it.
    public var gestureVelocity: CGFloat
    /// Creates an open state; `mode` defaults to the grid.
    public init(page: PageID, focus: WidgetID? = nil, mode: NookMode = .grid, reason: OpenReason, gestureVelocity: CGFloat = 0) {
        self.page = page; self.focus = focus; self.mode = mode; self.reason = reason
        self.gestureVelocity = gestureVelocity
    }
}

/// Written ONLY by its owner (the shell's per-display view model, or a preview stage). Views read it.
@MainActor @Observable public final class NotchSceneModel {
    /// The visible presentation (ARCHITECTURE.md §4.2).
    public var phase: NotchPhase = .idle
    /// Per-display geometry (`ThemeResolver.layout`).
    public var layout: NotchLayout
    /// Per-surface theme (`ThemeResolver.theme`); system accessibility flags are merged in by the canvas.
    public var theme: CrannyTheme
    /// The activity in the wings (compact, the top row of a peek, the HUD in the open header).
    public var primary: ActivityID?
    /// The second activity: the satellite bubble beside the compact shape.
    public var satellite: ActivityID?
    /// An activity of this display's lineup with a message for the open header (`OpenHeaderActivity`, e.g. the
    /// Pause Live Activities confirmation), whatever its rank: it takes the header row while the panel is open, unless
    /// a HUD is the primary. The owner picks it; stages leave it nil.
    public var headerActivity: ActivityID?
    /// Peek rows, top to bottom (at most 4 are drawn).
    public var peekRows: [ActivityID] = []
    /// Stages (Settings preview, onboarding) put `RegisteredActivity.makeSample()` instances here; the canvas
    /// prefers them over the registry's live objects. The shell leaves it empty.
    public var sampleActivities: [ActivityID: any LiveActivity] = [:]
    /// The open presentation; nil unless `phase == .open`.
    public var open: OpenState?
    /// The pin (⌘P) is on.
    public var pinned = false
    /// The light-layer palette (`ThemeResolver.ambientPalette`); changes cross-fade (`colorShift`).
    public var ambient: AmbientPalette = .afterglow
    /// One-shot delight to play (DESIGN.md §5.5). The owner applies the caps (one at a time, not paused,
    /// not in full screen, not under Instant) and bumps `delightSerial`; NotchUI plays each serial once, as its
    /// reduced variant under Calm and Reduce Motion. Sources: activities' `delight`, track change (`.songRipple`),
    /// first open (`.firstLight`), file caught (`.gulp`).
    public var delight: DelightMoment?
    /// Bumped by the owner for every delight to play; NotchUI plays each value once.
    public var delightSerial = 0
    /// Live rubber-band offset from a gesture in progress (pt; +y = down).
    public var gestureTranslation: CGSize = .zero
    /// Facts for feature views (`@Environment(\.notchContext)`); the canvas keeps `phase` and `layout` in step.
    public var context = NotchContext()
    /// The widget that has keyboard focus or is in a focus mode (`@Environment(\.notchFocusedWidget)`). The owner
    /// mirrors `NotchUIActions.focusWidget` and `OpenState.focus` into it.
    public var focusedWidget: WidgetID?
    /// Hold-⌘ hints are visible (`@Environment(\.notchShowsCommandHints)`).
    public var showsCommandHints = false
    /// The last interaction was the keyboard: focus rings show (`@Environment(\.notchKeyboardNavigation)`).
    public var keyboardNavigation = false
    /// Drop and scroll zones of this canvas (the shell routes AppKit events to them).
    public let zones: NotchZones

    /// A scene for one display or stage.
    public init(layout: NotchLayout, theme: CrannyTheme, zones: NotchZones = NotchZones()) {
        self.layout = layout; self.theme = theme; self.zones = zones
    }

    /// The shape for the current state (pure function of the model + layout, DESIGN.md §3.3).
    public var geometry: NotchGeometry {
        switch phase {
        case .hidden: .zero
        case .idle: layout.closed
        case .breath: layout.hover
        case .compact: layout.compact(primarySlot, label: middleLabelWidth)
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
    /// Displays without a notch: width of the compact middle label (`LiveActivity.middleLabel`, ≤ 160 pt) that
    /// `geometry` puts between the wings; 0 = no label (the 12-pt gap). The owner writes
    /// `MiddleLabelMetrics.width(of: primary.middleLabel, layout: layout)` whenever the primary or its label
    /// changes. Ignored on notched displays, where the camera housing is the middle (DESIGN.md §3.5).
    public var middleLabelWidth: CGFloat = 0
    /// The panel is on screen and not occluded (`NSWindow.occlusionState`). The owner clears it while the panel
    /// is covered, so the light layer and other effects pause (DESIGN.md §4.7; widgets read
    /// `@Environment(\.notchIsOnScreen)`). Stages leave it on.
    public var isVisibleOnScreen = true
}

/// Callbacks from the views to the owner. Stages pass no-ops.
public struct NotchUIActions {
    /// A tab was chosen (click, ⌘1–⌘5, ⌃Tab).
    public var selectPage: @MainActor (PageID) -> Void = { _ in }
    /// Pin button or ⌘P.
    public var togglePin: @MainActor () -> Void = {}
    /// Reserved: the palette opens through `setMode(.palette)`.
    public var showPalette: @MainActor () -> Void = {}
    /// Settings button or ⌘,.
    public var openSettings: @MainActor () -> Void = {}
    /// Esc at the end of the chain, or a palette command that closes the panel.
    public var close: @MainActor () -> Void = {}
    /// Click on the compact shape or a peek row: open focused on that activity's widget.
    public var activityTapped: @MainActor (ActivityID) -> Void = { _ in }
    /// Click on the satellite: swap it with the primary.
    public var satelliteTapped: @MainActor () -> Void = {}
    /// The layout editor (and the card's ⋯ menu) changed the pages: store them in `CoreSettings.pages`.
    public var commitLayout: @MainActor ([NookPage]) -> Void = { _ in }
    /// ⌘K / ⌘E / Esc chain / focus mode: NotchUI asks, the owner writes `open.mode`.
    public var setMode: @MainActor (NookMode) -> Void = { _ in }
    /// Keyboard focus moved to a widget (nil = none); the owner mirrors it into `focusedWidget`.
    public var focusWidget: @MainActor (WidgetID?) -> Void = { _ in }
    /// VoiceOver "Dismiss" action and swipe-up on the satellite.
    public var dismissActivity: @MainActor (ActivityID) -> Void = { _ in }
    /// VoiceOver "Open" on the collapsed notch.
    public var open: @MainActor () -> Void = {}
    /// No-op callbacks (stages, previews).
    public init() {}
}
