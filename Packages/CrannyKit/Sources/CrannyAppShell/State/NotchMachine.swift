// CrannyAppShell/State/NotchMachine.swift — the per-display state machine (ARCHITECTURE.md §4), pure and Equatable.
// WP0 implements the rows needed for the foundation behaviour (hover dwell → open, leave + grace → close,
// click, hot key, Esc, pin, holds); WP13 completes §4.4 (peeks, swipes, drags, hiding, timeouts).
// The reducer never touches AppKit (everything here is `nonisolated` and pure): the view model executes the effects.
import CrannyCore
import CrannyNotchUI
import Foundation

nonisolated struct NotchMachineState: Equatable {
    nonisolated enum Surface: Equatable { case closed, peek(Peek), open(OpenState) }      // OpenState: §4.12
    nonisolated enum Peek: Equatable { case hover, auto(ActivityID, until: TimeInterval) }
    nonisolated enum Hover: Equatable { case outside, dwelling(since: TimeInterval), inside }
    nonisolated enum Hidden: Equatable { case fullScreen, excludedApp, locked, displaysAsleep, idleHandle, notThisDisplay }

    var surface: Surface = .closed
    var hover: Hover = .outside
    var hidden: Hidden? = nil
    var pinned = false
    var holds: Set<String> = []          // NotchControl.setHoldOpen reasons + "menu", "drag", "typing"
    var graceDeadline: TimeInterval?     // pending close after leaving the exit zone

    var isOpen: Bool { if case .open = surface { true } else { false } }
    var isClosed: Bool { surface == .closed }
}

/// Settings and facts the reducer reads; the view model snapshots them for every input.
nonisolated struct NotchMachineConfig: Equatable {
    var openMode: OpenMode = .hover
    var hoverDelay: TimeInterval = HoverIntent.defaultDelay.seconds
    var closeOnLeave = true
    var quickPeekOnHover = true
    var lastPage: PageID = .nook
    var voiceOverRunning = false
    /// The arbiter has a primary activity on this display (compact is showing).
    var hasPrimaryActivity = false
}

nonisolated enum NotchInput: Equatable {
    /// The pointer entered the entry zone (closed) or came back inside the exit zone (open/peek).
    case pointerEntered
    /// The pointer left the entry zone (closed) or the exit zone (open/peek).
    case pointerLeft
    /// The dwell scheduled on entry elapsed; `shouldOpen` = `HoverIntent.shouldOpen(…)` at that moment.
    case dwellElapsed(shouldOpen: Bool)
    case graceElapsed
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
    /// The arbiter asks for a one-off peek of an activity until `until` (systemUptime).
    case autoPeek(ActivityID, until: TimeInterval)
}

nonisolated enum NotchEffect: Equatable {
    case scheduleDwell(TimeInterval)
    case cancelDwell
    case scheduleGrace(TimeInterval)
    case cancelGrace
    case makeKey
    case relinquishKey
    case emit(NotchEvent)
}

nonisolated enum NotchMachine {
    /// §4.2: what is drawn.
    static func phase(_ s: NotchMachineState, config: NotchMachineConfig) -> NotchPhase {
        if s.hidden != nil { return .hidden }
        switch s.surface {
        case .open: return .open
        case .peek: return .peek
        case .closed:
            if config.hasPrimaryActivity { return .compact }
            if case .dwelling = s.hover, config.openMode != .shortcutOnly { return .breath }
            return .idle
        }
    }

    /// Whether leaving may close (§4.4: closeOnLeave; not pinned; no holds).
    static func mayAutoClose(_ s: NotchMachineState, config: NotchMachineConfig) -> Bool {
        config.closeOnLeave && !s.pinned && s.holds.isEmpty
    }

    static func reduce(_ state: NotchMachineState, _ input: NotchInput, now: TimeInterval,
                       config: NotchMachineConfig) -> (NotchMachineState, [NotchEffect]) {
        var s = state
        var fx: [NotchEffect] = []

        func open(page: PageID?, focus: WidgetID? = nil, reason: OpenReason) {
            let wasOpen = s.isOpen
            s.surface = .open(OpenState(page: page ?? config.lastPage, focus: focus, reason: reason))
            s.hover = s.hover == .outside ? .outside : .inside
            if s.graceDeadline != nil { s.graceDeadline = nil; fx.append(.cancelGrace) }
            fx.append(.cancelDwell)
            if reason == .keyboard { fx.append(.makeKey) }
            if !wasOpen { fx.append(.emit(.opened(reason))) }
        }
        func close() {
            guard !s.isClosed else { return }
            s.surface = .closed
            s.graceDeadline = nil
            // A pointer still over the shape must leave and come back before it opens again.
            s.hover = s.hover == .outside ? .outside : .inside
            fx += [.cancelDwell, .cancelGrace, .relinquishKey, .emit(.closed)]
        }
        func scheduleGraceIfLeft() {
            guard !s.isClosed, s.hover == .outside, s.graceDeadline == nil, mayAutoClose(s, config: config) else { return }
            s.graceDeadline = now + HoverIntent.closeGrace
            fx.append(.scheduleGrace(HoverIntent.closeGrace))
        }

        switch input {
        case .pointerEntered:
            if s.isClosed {
                guard s.hidden == nil, s.hover == .outside, config.openMode != .shortcutOnly else { break }
                if config.hasPrimaryActivity {
                    guard config.quickPeekOnHover else { s.hover = .inside; break }
                    s.hover = .dwelling(since: now)
                    fx.append(.scheduleDwell(HoverIntent.peekDwell))
                } else {
                    s.hover = .dwelling(since: now)
                    fx.append(.scheduleDwell(config.hoverDelay))
                }
            } else {
                s.hover = .inside
                if s.graceDeadline != nil { s.graceDeadline = nil; fx.append(.cancelGrace) }
            }

        case .pointerLeft:
            if s.isClosed {
                if case .dwelling = s.hover { fx.append(.cancelDwell) }
                s.hover = .outside
            } else {
                s.hover = .outside
                scheduleGraceIfLeft()
            }

        case .dwellElapsed(let shouldOpen):
            guard s.isClosed, case .dwelling = s.hover, s.hidden == nil else { break }
            // Click mode (and VoiceOver) keep the breath: it says "noticed", the click opens.
            guard config.openMode == .hover, !config.voiceOverRunning else { break }
            guard shouldOpen else { s.hover = .inside; break }       // passing through: no open until re-entry
            if config.hasPrimaryActivity {
                s.surface = .peek(.hover)
                s.hover = .inside
            } else {
                open(page: nil, reason: .hover)
                s.hover = .inside
            }

        case .graceElapsed:
            guard s.graceDeadline != nil else { break }
            s.graceDeadline = nil
            guard s.hover == .outside, mayAutoClose(s, config: config) else { break }
            close()

        case .click:
            guard s.hidden == nil else { break }
            switch s.surface {
            case .closed, .peek: open(page: nil, reason: .click)
            case .open: break
            }

        case .hotKey:
            if s.isOpen { close() } else { open(page: nil, reason: .keyboard) }

        case .escape:
            guard case .open(var o) = s.surface else { close(); break }
            if o.mode != .grid {                                          // palette / edit / focus → grid first
                o.mode = .grid
                s.surface = .open(o)
            } else {
                close()
            }

        case let .open(page, focus, reason):
            guard s.hidden == nil else { break }
            open(page: page, focus: focus, reason: reason)

        case .close:
            close()

        case .setPinned(let pinned):
            guard s.pinned != pinned else { break }
            s.pinned = pinned
            fx.append(.emit(.pinned(pinned)))
            if !pinned { scheduleGraceIfLeft() }

        case let .hold(reason, on):
            if on { s.holds.insert(reason) } else { s.holds.remove(reason) }
            if !on { scheduleGraceIfLeft() }

        case .setMode(let mode):
            guard case .open(var o) = s.surface else { break }
            o.mode = mode
            s.surface = .open(o)

        case let .autoPeek(id, until):
            guard s.hidden == nil, !s.isOpen else { break }
            s.surface = .peek(.auto(id, until: until))

        case .selectPage(let page):
            guard case .open(var o) = s.surface, o.page != page else { break }
            o.page = page
            o.mode = .grid
            s.surface = .open(o)
            fx.append(.emit(.pageChanged(page)))
        }
        return (s, fx)
    }
}
