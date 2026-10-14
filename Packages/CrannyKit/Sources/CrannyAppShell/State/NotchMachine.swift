// CrannyAppShell/State/NotchMachine.swift — the per-display reducer (ARCHITECTURE.md §4.2–§4.8), pure:
// `reduce(state, input, now, config) -> (state, [effect])`. It never touches AppKit; `NotchViewModel` runs the
// effects (timers, key focus, haptics, events). Every row of the §4.4 table is a case below and has a test.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import UniformTypeIdentifiers

nonisolated enum NotchMachine {
    /// DESIGN.md §4.6 menu-bar courtesy: the wings come back this long after the pointer leaves the band.
    static let wingsReturnDelay: TimeInterval = 1.5
    /// §4.4: after a drop in the catch state, the shape gulps for 0.25 s before it returns.
    static let catchGulp: TimeInterval = 0.25

    /// §4.2: what is drawn.
    static func phase(_ s: NotchMachineState, config: NotchMachineConfig) -> NotchPhase {
        if s.hidden != nil { return .hidden }
        switch s.surface {
        case .open: return .open
        case .peek: return .peek
        case .closed:
            if s.calibrating { return .breath }                                  // frozen in hover while fitting
            if compactIsVisible(s, config: config) { return .compact }
            if case .dwelling = s.hover, config.openMode != .shortcutOnly { return .breath }
            return .idle
        }
    }

    /// The wings show the primary: closed, not collapsed by the inactivity timeout, not retracted for the menu bar.
    static func compactIsVisible(_ s: NotchMachineState, config: NotchMachineConfig) -> Bool {
        s.isClosed && config.primary != nil && !s.compactCollapsed && !s.wingsRetracted && !s.calibrating
    }

    /// Whether leaving may close the open panel (§4.4: closeOnLeave; not pinned; no holds — the panel being key
    /// and a tracking menu are holds too; not in a holding mode; not in Demo mode).
    static func mayAutoClose(_ s: NotchMachineState, config: NotchMachineConfig) -> Bool {
        config.closeOnLeave && !s.pinned && s.holds.isEmpty && !s.modeHoldsOpen && !s.environment.demoMode
    }

    static func reduce(_ state: NotchMachineState, _ input: NotchInput, now: TimeInterval,
                       config: NotchMachineConfig) -> (NotchMachineState, [NotchEffect]) {
        var reduction = NotchReduction(s: state, config: config, now: now)
        reduction.apply(input)
        reduction.syncIdleTimers()
        return (reduction.s, reduction.fx)
    }
}

/// One reduction: the state being built and the effects it collects, in order.
nonisolated struct NotchReduction {
    var s: NotchMachineState
    var fx: [NotchEffect] = []
    let config: NotchMachineConfig
    let now: TimeInterval

    init(s: NotchMachineState, config: NotchMachineConfig, now: TimeInterval) {
        self.s = s; self.config = config; self.now = now
    }

    // MARK: Inputs

    mutating func apply(_ input: NotchInput) {
        switch input {
        case .pointerEntered: pointerEntered()
        case .pointerLeft: pointerLeft()
        case .dwellElapsed(let shouldOpen): dwellElapsed(shouldOpen: shouldOpen)
        case .dwellRetry:
            s.timers.remove(.dwell)
            guard s.isClosed, case .dwelling = s.hover, !s.blocksInput else { break }
            schedule(.dwell, dwell(config.hasPrimaryActivity ? HoverIntent.peekDwell : config.hoverDelay))
        case .timerElapsed(let timer): timerElapsed(timer)
        case .click:
            guard !s.blocksInput, !s.isOpen else { break }
            open(page: config.primaryWidgetPage, focus: config.primaryWidget, reason: .click)
        case .hotKey:
            if s.isOpen { close() } else if !s.blocksInput { open(page: nil, focus: nil, reason: .keyboard) }
        case .escape: escape()
        case let .open(page, focus, reason):
            guard !s.blocksInput else { break }
            open(page: page, focus: focus, reason: reason)
        case .close: close()
        case .setPinned(let pinned):
            guard s.pinned != pinned else { break }
            s.pinned = pinned
            fx.append(.emit(.pinned(pinned)))
            if pinned { cancel(.grace) } else { scheduleGraceIfLeft() }
        case let .hold(reason, on): hold(reason, on)
        case .setMode(let mode): setMode(mode)
        case .selectPage(let page):
            guard var o = s.openState, o.page != page else { break }
            o.page = page
            o.mode = .grid
            s.surface = .open(o)
            fx.append(.emit(.pageChanged(page)))
        case .setFocus(let widget):
            guard var o = s.openState, o.focus != widget else { break }
            o.focus = widget
            s.surface = .open(o)
        case let .autoPeek(id, until): autoPeek(id, until: until)
        case let .swipe(direction, target): swipe(direction, over: target)
        case .fileDragEntered(let types): fileDragEntered(types)
        case .fileDragEnded: fileDragEnded()
        case .filesDropped(let count): filesDropped(count)
        case .environment(let environment): setEnvironment(environment)
        case .activityChanged:
            s.compactCollapsed = false
            s.handleHidden = false
            cancel(.compactIdle)                                                 // re-armed for the new revision
            cancel(.handleIdle)
        case .configChanged: break                                               // `syncIdleTimers` does the work
        case .band(let position): band(position)
        case .calibration(let on): s.calibrating = on
        }
    }

    // MARK: Hover (§4.3, §4.4, DESIGN.md §4.6)

    private mutating func pointerEntered() {
        s.handleHidden = false                                                   // geometric: works while invisible
        if s.wingsRetracted { s.wingsRetracted = false; cancel(.wingsReturn) }   // the pointer came for the notch
        guard !s.blocksInput else { return }
        switch s.surface {
        case .closed:
            guard s.hover == .outside else { return }
            guard config.openMode != .shortcutOnly else { s.hover = .inside; return }
            if config.hasPrimaryActivity {
                guard config.quickPeekOnHover else { s.hover = .inside; return }
                s.hover = .dwelling(since: now)
                schedule(.dwell, dwell(HoverIntent.peekDwell))
            } else {
                s.hover = .dwelling(since: now)
                schedule(.dwell, dwell(config.hoverDelay))
            }
        case .peek, .open:
            s.hover = .inside
            cancel(.grace)
            if s.isCatching { cancel(.catchEnd) }
        }
    }

    private mutating func pointerLeft() {
        switch s.surface {
        case .closed:
            cancel(.dwell)
            s.hover = .outside
        case .peek, .open:
            s.hover = .outside
            if s.isCatching { scheduleCatchEnd(HoverIntent.closeGrace) } else { scheduleGraceIfLeft() }
        }
    }

    private mutating func dwellElapsed(shouldOpen: Bool) {
        s.timers.remove(.dwell)
        guard s.isClosed, case .dwelling = s.hover, !s.blocksInput else { return }
        // Click mode (and VoiceOver) keep the breath: it says "noticed", the click opens.
        guard config.openMode == .hover, !config.voiceOverRunning else { return }
        guard shouldOpen else { s.hover = .inside; return }                     // passing through: no open until re-entry
        if config.hasPrimaryActivity {
            s.surface = .peek(.hover)
        } else {
            open(page: nil, focus: nil, reason: .hover)
        }
        s.hover = .inside
    }

    /// Full-screen Spaces (`.alertsAndHUD`) need a longer dwell: tabs and toolbars live up there.
    func dwell(_ delay: TimeInterval) -> TimeInterval {
        s.environment.restrictsToAlerts ? max(delay, HoverIntent.fullScreenDwell) : delay
    }

    // MARK: Open and close

    mutating func open(page: PageID?, focus: WidgetID?, mode: NookMode = .grid, reason: OpenReason) {
        let previous = s.openState
        // Re-opening an open panel without naming a page keeps the page it shows.
        let page = page ?? previous?.page ?? config.lastPage
        s.surface = .open(OpenState(page: page, focus: focus, mode: mode, reason: reason))
        if s.hover != .outside { s.hover = .inside }
        s.handleHidden = false
        for timer in [NotchTimer.dwell, .grace, .peekEnd, .catchEnd] { cancel(timer) }
        // Keyboard opens take focus; so does a programmatic open that names a widget ("gives it keyboard focus").
        if reason == .keyboard || (focus != nil && [.programmatic, .activity, .tutorial].contains(reason)) {
            fx.append(.makeKey)
        }
        if let previous {
            if previous.page != page { fx.append(.emit(.pageChanged(page))) }
        } else {
            fx.append(.emit(.opened(reason)))
        }
    }

    mutating func close() {
        switch s.surface {
        case .closed:
            return
        case .peek:
            s.surface = .closed
        case .open:
            s.surface = .closed
            fx += [.relinquishKey, .emit(.closed)]
            // An explicit close ends the pin: the next hover-open must not come back pinned.
            if s.pinned { s.pinned = false; fx.append(.emit(.pinned(false))) }
        }
        for timer in [NotchTimer.dwell, .grace, .peekEnd, .catchEnd] { cancel(timer) }
        // A pointer still over the shape must leave and come back before it opens again.
        if s.hover != .outside { s.hover = .inside }
    }

    mutating func scheduleGraceIfLeft() {
        guard s.hover == .outside, !s.timers.contains(.grace) else { return }
        switch s.surface {
        case .closed:
            return
        case .peek:
            guard s.holds.isEmpty else { return }
        case .open:
            guard !s.isCatching, NotchMachine.mayAutoClose(s, config: config) else { return }
        }
        schedule(.grace, HoverIntent.closeGrace)
    }

    private mutating func escape() {
        guard var o = s.openState else { close(); return }
        switch o.mode {
        case .palette, .editLayout, .focus:                                     // leave the mode first
            o.mode = .grid
            s.surface = .open(o)
            scheduleGraceIfLeft()
        case .grid, .catchFiles:
            close()
        }
    }

    private mutating func hold(_ reason: String, _ on: Bool) {
        if on {
            s.holds.insert(reason)
            cancel(.grace)
            if reason == NotchMachineState.dropHold { cancel(.catchEnd) }        // the catch waits for the payload
        } else if s.holds.remove(reason) != nil {
            // The dropped promises were handed over: the catch state gulps and returns.
            if reason == NotchMachineState.dropHold, s.isCatching, s.fileDrag == nil { scheduleCatchEnd(NotchMachine.catchGulp) }
            scheduleGraceIfLeft()
        }
    }

    private mutating func setMode(_ mode: NookMode) {
        guard var o = s.openState, o.mode != mode else { return }
        let wasPalette = o.mode == .palette
        o.mode = mode
        s.surface = .open(o)
        if mode == .palette && !wasPalette { fx.append(.emit(.paletteOpened)) }
        if s.modeHoldsOpen { cancel(.grace) } else { scheduleGraceIfLeft() }
    }

    // MARK: Peeks (§4.7)

    private mutating func autoPeek(_ id: ActivityID, until: TimeInterval) {
        guard !s.blocksInput, !s.isOpen, s.surface != .peek(.hover) else { return }   // a hover peek already shows it
        s.handleHidden = false
        s.surface = .peek(.auto(id, until: until))
        cancel(.grace)
        if until.isFinite { schedule(.peekEnd, max(until - now, 0)) } else { cancel(.peekEnd) }
    }

    // MARK: Timers

    private mutating func timerElapsed(_ timer: NotchTimer) {
        guard s.timers.remove(timer) != nil else { return }                     // cancelled meanwhile
        switch timer {
        case .dwell:
            break                                                                // `dwellElapsed` carries the decision
        case .grace:
            guard s.hover == .outside else { return }
            switch s.surface {
            case .closed: break
            case .peek: if s.holds.isEmpty { close() }
            case .open: if !s.isCatching, NotchMachine.mayAutoClose(s, config: config) { close() }
            }
        case .peekEnd:
            guard case .peek(.auto) = s.surface, s.hover != .inside else { return }   // a hover keeps it
            close()
        case .catchEnd:
            guard var o = s.openState, case .catchFiles = o.mode else { return }
            guard s.fileDrag == nil || s.hover == .outside else { return }       // still dragging over it
            guard !s.holds.contains(NotchMachineState.dropHold) else { return }  // promises still resolving
            s.holds.remove(NotchMachineState.dragHold)
            if s.pinned { o.mode = .grid; s.surface = .open(o) } else { close() }
        case .inactivity:
            if idleCloseAllowed { close() }
        case .compactIdle:
            if NotchMachine.compactIsVisible(s, config: config) { s.compactCollapsed = true }
        case .handleIdle:
            if handleMayHide { s.handleHidden = true }
        case .wingsReturn:
            s.wingsRetracted = false
        }
    }
}
