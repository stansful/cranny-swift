// CrannyAppShell/State/NotchMachineState.swift — the values of the per-display state machine (ARCHITECTURE.md §4.1):
// its state, the environment facts and settings it reads, its inputs and its effects. Everything is
// `nonisolated`, pure and Equatable so the reducer (`NotchMachine.swift`) is tested without windows.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import UniformTypeIdentifiers

// MARK: - State

nonisolated struct NotchMachineState: Equatable {
    nonisolated enum Surface: Equatable { case closed, peek(Peek), open(OpenState) }      // OpenState: §4.12
    nonisolated enum Peek: Equatable { case hover, auto(ActivityID, until: TimeInterval) }
    nonisolated enum Hover: Equatable { case outside, dwelling(since: TimeInterval), inside }
    nonisolated enum Hidden: Equatable { case fullScreen, excludedApp, locked, displaysAsleep, idleHandle, notThisDisplay }

    var surface: Surface = .closed
    var hover: Hover = .outside
    var pinned = false
    /// `NotchControl.setHoldOpen` reasons plus the shell's own (`typing`, `menu`, `popover`, `drag`, `share`, §4.5).
    var holds: Set<String> = []
    /// Timers the reducer has scheduled and not yet cancelled (the view model runs one sleep per timer).
    var timers: Set<NotchTimer> = []
    /// Facts about the machine and this display (§4.8, §4.9); `hidden` derives from them.
    var environment = NotchEnvironment()
    /// No-notch handle faded out: "Hide when idle" elapsed, or swiped up (DESIGN.md §3.5).
    var handleHidden = false
    /// The compact inactivity timeout collapsed the wings until the next revision (§4.7).
    var compactCollapsed = false
    /// Menu-bar courtesy: the wings retracted while the pointer is beside them in the band (DESIGN.md §4.6).
    var wingsRetracted = false
    /// Appearance ▸ Notch fit is being dragged: the closed shape freezes in the breath (DESIGN.md §3.1).
    var calibrating = false
    /// A file drag from any app is in progress, with the dragged types (nil = none).
    var fileDrag: [UTType]?

    var isOpen: Bool { if case .open = surface { true } else { false } }
    var isClosed: Bool { surface == .closed }
    var isPeeking: Bool { if case .peek = surface { true } else { false } }
    var openState: OpenState? { if case .open(let o) = surface { o } else { nil } }
    var isCatching: Bool { if case .catchFiles? = openState?.mode { true } else { false } }

    /// §4.2: what hides the panel (content alpha 0, so it is click-through). Hard reasons win over the
    /// display selection, which wins over the idle handle. An open panel on a display the pointer left stays
    /// until it closes (`.pointer` selection, §4.9).
    var hidden: Hidden? {
        if let hard = environment.hardHidden { return hard }
        if environment.notThisDisplay && !isOpen { return .notThisDisplay }
        if handleHidden && isClosed { return .idleHandle }
        return nil
    }
    /// Hidden for a reason that also blocks input (everything but the idle handle, which any input brings back).
    var blocksInput: Bool { hidden != nil && hidden != .idleHandle }

    /// Palette, edit layout and focus mode hold the panel open (§4.5).
    var modeHoldsOpen: Bool {
        switch openState?.mode {
        case .palette?, .editLayout?, .focus?: true
        case .grid?, .catchFiles?, nil: false
        }
    }

    // MARK: Shell-owned hold reasons (§4.5); module reasons are namespaced ("notes.editing").

    /// The panel is key (opened by the hot key, a text field clicked, `requestKeyboardFocus`): §4.4 "panel not key".
    static let typingHold = "typing"
    /// An `NSMenu` is tracking (a context menu in the panel, the menu bar extra's menu).
    static let menuHold = "menu"
    /// An `NSPopover` shown from inside the panel.
    static let popoverHold = "popover"
    /// A file drag is in progress.
    static let dragHold = "drag"
    /// A share or AirDrop sheet presented through `NotchControl`.
    static let shareHold = "share"
}

/// One-shot timers of the machine. Every one is a single `Task.sleep`, scheduled by an input; none repeats.
nonisolated enum NotchTimer: String, Hashable, Sendable, CaseIterable {
    case dwell          // hover delay / quick-peek dwell
    case grace          // close grace after leaving the exit zone
    case peekEnd        // an auto-peek's `until`
    case catchEnd       // the catch state returns to the previous surface
    case inactivity     // `openInactivityTimeout`
    case compactIdle    // `compactInactivityTimeout`
    case handleIdle     // `handleIdleDelay` (no-notch displays)
    case wingsReturn    // menu-bar courtesy: the wings come back
}

// MARK: - Environment

/// What the coordinator knows about the machine and this display. The reducer turns it into `hidden`.
nonisolated struct NotchEnvironment: Equatable {
    var isLocked = false
    var displaysAsleep = false
    /// A full-screen app is in front on this display (§5.7).
    var fullScreen = false
    /// An app from `CoreSettings.excludedBundleIDs` is frontmost on this display.
    var excludedApp = false
    /// `.pointer` display selection and the pointer is on another display.
    var notThisDisplay = false
    var policy: FullScreenPolicy = .alertsAndHUD
    /// Demo mode: never auto-closes or hides; acts as pinned + `.showAll` (§4.4).
    var demoMode = false

    /// Hiding that closes the panel and blocks every input (§4.4, §4.8).
    var hardHidden: NotchMachineState.Hidden? {
        if isLocked { return .locked }
        if displaysAsleep { return .displaysAsleep }
        guard !demoMode, policy == .hideAll else { return nil }
        if fullScreen { return .fullScreen }
        if excludedApp { return .excludedApp }
        return nil
    }
    /// `.alertsAndHUD` with a full-screen (or excluded) app in front: only P0/P1, hover dwell ≥ 0.40 s.
    var restrictsToAlerts: Bool {
        !demoMode && policy == .alertsAndHUD && (fullScreen || excludedApp)
    }
}

// MARK: - Config

/// Settings and facts the reducer reads; the view model snapshots them for every input.
nonisolated struct NotchMachineConfig: Equatable {
    var openMode: OpenMode = .hover
    var hoverDelay: TimeInterval = HoverIntent.defaultDelay.seconds
    var closeOnLeave = true
    /// "Quick peek on hover", and this display shows peeks.
    var quickPeekOnHover = true
    var lastPage: PageID = .nook
    var voiceOverRunning = false
    /// The arbiter's lineup on this display (§4.6).
    var primary: ActivityID?
    var satellite: ActivityID?
    /// Click on compact/peek: the primary's `opensWidget` and the page that holds it.
    var primaryWidget: WidgetID?
    var primaryWidgetPage: PageID?
    var openInactivityTimeout: TimeInterval = 0
    var compactInactivityTimeout: TimeInterval = 0
    /// The display has no hardware notch, so the closed shape is a handle (DESIGN.md §3.5).
    var hasHandle = false
    var hidesIdleHandle = false
    var handleIdleDelay: TimeInterval = 10
    var swipeOpenClose = true
    var swipeToDismiss = true
    var trackSwipe = true
    /// A Tray is registered (`services.tray != nil`): file drags open the catch state.
    var acceptsFileDrags = false
    var menuBarCourtesy = true

    var hasPrimaryActivity: Bool { primary != nil }
}

// MARK: - Inputs and effects

/// Where a two-finger swipe began (GestureRouter decides from the event location).
nonisolated enum SwipeTarget: Equatable, Sendable { case shape, satellite, header }

/// Where the pointer is relative to the menu bar band (menu-bar courtesy, DESIGN.md §4.6).
nonisolated enum BandPosition: Equatable, Sendable {
    /// In the band within 24 pt beside the compact wings.
    case courtesy
    /// Elsewhere in the band.
    case band
    case outside
}

/// UI sounds the machine asks for (system sounds, DESIGN.md §14.3; played only with `uiSounds`, never in Demo mode).
nonisolated enum UISound: String, Equatable, Sendable { case pop = "Pop" }

nonisolated enum NotchInput: Equatable {
    /// The pointer entered the entry zone (closed) or came back inside the exit zone (open/peek).
    case pointerEntered
    /// The pointer left the entry zone (closed) or the exit zone (open/peek).
    case pointerLeft
    /// The dwell scheduled on entry elapsed; `shouldOpen` = `HoverIntent.shouldOpen(…)` at that moment.
    case dwellElapsed(shouldOpen: Bool)
    case timerElapsed(NotchTimer)
    case click
    /// Open Cranny hot key (⌃⌥N): toggles.
    case hotKey
    case escape
    case open(page: PageID?, focus: WidgetID?, reason: OpenReason)
    case close
    case setPinned(Bool)
    case hold(String, Bool)
    case setMode(NookMode)
    case selectPage(PageID)
    /// Moves the open panel's focus to a widget (type-to-capture, `NotchControl.open(focus:)` while open).
    case setFocus(WidgetID?)
    /// The coordinator asks for a one-off peek of an activity until `until` (systemUptime; `.infinity` = held).
    case autoPeek(ActivityID, until: TimeInterval)
    /// A committed two-finger swipe (`SwipeTracker`) and where it began.
    case swipe(SwipeDirection, target: SwipeTarget)
    /// A file drag came within the drag proximity, or over the open panel, with these types.
    case fileDragEntered([UTType])
    /// The file drag ended without a drop on this panel.
    case fileDragEnded
    /// Files were dropped on this panel (`count` > 0 when something took them).
    case filesDropped(count: Int)
    case environment(NotchEnvironment)
    /// An activity shown on this display has a new revision: unhides the handle and the collapsed wings.
    case activityChanged
    /// The config changed (lineup, settings): re-evaluates the idle timers, changes nothing else.
    case configChanged
    case band(BandPosition)
    case calibration(Bool)
}

nonisolated enum NotchEffect: Equatable {
    case schedule(NotchTimer, after: TimeInterval)
    case cancel(NotchTimer)
    case makeKey
    case relinquishKey
    case emit(NotchEvent)
    case haptic(HapticPattern)
    /// Swipe-up dismissal (§4.7): the arbiter remembers the activity's revision.
    case dismissActivity(ActivityID)
    /// Horizontal swipe over the primary: `activity.handle(_:)`.
    case activityGesture(ActivityID, ActivityGesture)
    case playSound(UISound)
}
