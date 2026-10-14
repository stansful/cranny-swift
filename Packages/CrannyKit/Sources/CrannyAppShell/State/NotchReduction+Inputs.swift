// CrannyAppShell/State/NotchReduction+Inputs.swift — the rest of the per-display reducer (ARCHITECTURE.md §4.4):
// swipes, file drags, the environment, menu-bar courtesy and the idle timers, plus the timer bookkeeping every
// input shares. Pure like `NotchMachine.swift`; split only to keep each file small.
import CoreGraphics
import CrannyCore
import CrannyNotchUI
import Foundation
import UniformTypeIdentifiers

nonisolated extension NotchReduction {
    // MARK: Swipes (§4.4, DESIGN.md §4.4)

    mutating func swipe(_ direction: SwipeDirection, over target: SwipeTarget) {
        guard !s.blocksInput else { return }
        let compact = NotchMachine.compactIsVisible(s, config: config)
        switch (s.surface, direction, target) {
        case (.closed, .down, .shape):
            guard config.swipeOpenClose else { return }
            fx.append(.haptic(.alignment))
            open(page: nil, focus: nil, reason: .swipe)
        case (.open, .up, .header):
            guard config.swipeOpenClose else { return }
            fx.append(.haptic(.alignment))
            close()
        case (.closed, .up, .satellite):
            guard config.swipeToDismiss, compact, let satellite = config.satellite else { return }
            fx += [.haptic(.alignment), .dismissActivity(satellite)]
        case (.closed, .up, .shape), (.peek, .up, .shape):
            if (compact || s.isPeeking), config.swipeToDismiss, let primary = config.primary {
                fx += [.haptic(.alignment), .dismissActivity(primary)]
                if s.isPeeking { close() }
            } else if s.isClosed, config.hasHandle, config.primary == nil, !s.handleHidden {
                fx.append(.haptic(.alignment))
                s.handleHidden = true                                            // until the next activity
            }
        case (.closed, .left, .shape), (.closed, .right, .shape), (.peek, .left, .shape), (.peek, .right, .shape):
            guard config.trackSwipe, compact || s.isPeeking, let primary = config.primary else { return }
            let gesture: ActivityGesture = direction == .left ? .swipeLeft : .swipeRight
            fx += [.haptic(.alignment), .activityGesture(primary, gesture), .emit(.activityGesture(primary, gesture))]
        default:
            break
        }
    }

    // MARK: File drags (§4.4, §5.5–§5.6)

    mutating func fileDragEntered(_ types: [UTType]) {
        s.fileDrag = types
        guard !s.blocksInput else { return }
        s.handleHidden = false
        s.holds.insert(NotchMachineState.dragHold)
        cancel(.grace)
        switch s.surface {
        case .closed, .peek:
            guard config.acceptsFileDrags else { return }
            open(page: nil, focus: nil, mode: .catchFiles(types), reason: .drag)
        case .open(var o):
            guard case .catchFiles = o.mode else { return }                     // the grid stays: widget zones take it
            o.mode = .catchFiles(types)
            s.surface = .open(o)
            cancel(.catchEnd)
        }
    }

    mutating func fileDragEnded() {
        guard s.fileDrag != nil else { return }
        s.fileDrag = nil
        s.holds.remove(NotchMachineState.dragHold)
        if s.isCatching { schedule(.catchEnd, HoverIntent.closeGrace) } else { scheduleGraceIfLeft() }
    }

    mutating func filesDropped(_ count: Int) {
        s.fileDrag = nil
        s.holds.remove(NotchMachineState.dragHold)
        if count > 0 { fx += [.emit(.filesCaught(count: count)), .haptic(.generic), .playSound(.pop)] }
        if s.isCatching { schedule(.catchEnd, count > 0 ? NotchMachine.catchGulp : HoverIntent.closeGrace) }
        else { scheduleGraceIfLeft() }
    }

    // MARK: Environment (§4.8, §4.9)

    mutating func setEnvironment(_ environment: NotchEnvironment) {
        let wasDemo = s.environment.demoMode
        s.environment = environment
        if environment.hardHidden != nil {
            close()
            cancel(.dwell)
            if case .dwelling = s.hover { s.hover = .inside }
        }
        if wasDemo && !environment.demoMode { scheduleGraceIfLeft() }
    }

    // MARK: Menu-bar courtesy (DESIGN.md §4.6)

    mutating func band(_ position: BandPosition) {
        switch position {
        case .courtesy:
            guard config.menuBarCourtesy, NotchMachine.compactIsVisible(s, config: config) || s.wingsRetracted else { return }
            s.wingsRetracted = true
            cancel(.wingsReturn)
        case .band:
            cancel(.wingsReturn)
        case .outside:
            if s.wingsRetracted, !s.timers.contains(.wingsReturn) { schedule(.wingsReturn, NotchMachine.wingsReturnDelay) }
        }
    }

    // MARK: Idle timers (armed while their condition holds, cancelled when it stops)

    var idleCloseAllowed: Bool {
        s.isOpen && !s.isCatching && s.hover == .outside && !s.pinned && s.holds.isEmpty && !s.modeHoldsOpen
            && !s.environment.demoMode
    }
    var handleMayHide: Bool {
        config.hidesIdleHandle && config.hasHandle && s.isClosed && config.primary == nil && s.hover == .outside
            && !s.handleHidden && s.hidden == nil
    }

    mutating func syncIdleTimers() {
        arm(.inactivity, config.openInactivityTimeout, when: config.openInactivityTimeout > 0 && idleCloseAllowed)
        arm(.compactIdle, config.compactInactivityTimeout,
            when: config.compactInactivityTimeout > 0 && NotchMachine.compactIsVisible(s, config: config)
                && s.hover == .outside && s.hidden == nil)
        arm(.handleIdle, config.handleIdleDelay, when: handleMayHide)
    }

    mutating func arm(_ timer: NotchTimer, _ delay: TimeInterval, when condition: Bool) {
        if condition { if !s.timers.contains(timer) { schedule(timer, delay) } } else { cancel(timer) }
    }

    mutating func schedule(_ timer: NotchTimer, _ delay: TimeInterval) {
        s.timers.insert(timer)
        fx.append(.schedule(timer, after: delay))
    }

    mutating func cancel(_ timer: NotchTimer) {
        guard s.timers.remove(timer) != nil else { return }
        fx.append(.cancel(timer))
    }
}
