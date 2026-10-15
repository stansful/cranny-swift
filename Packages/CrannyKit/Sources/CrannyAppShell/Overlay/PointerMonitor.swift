// CrannyAppShell/Overlay/PointerMonitor.swift — where the pointer is and how fast it moves (ARCHITECTURE.md §5.5).
// Two backends. Where macOS allows it (Input Monitoring or Accessibility granted), a listen-only event tap on its own
// thread (`PointerTap`): it keeps moves and drags far from every panel off the main thread, by a gate the coordinator
// publishes (`gateChanged`, `start(gate:_:)`). Otherwise global AND local NSEvent monitors (global monitors miss our own
// windows), which need no permission. Nothing ever asks for a permission: the tap is used only when it is enabled right
// after creation. While the tap runs, mouse-down monitors check on every press that it still does (a revoked grant
// leaves it disabled) and switch to the NSEvent monitors at once if not; so does the next hop after macOS disabled the
// tap and it stayed disabled when enabled again. Both report the kind of event and `NSEvent.mouseLocation` when it is
// handled (the tap once per hop for a run of one kind, `TapQueue`); the handler is O(displays) and allocation-free.
// Speed (measured from every event, by the tap on its thread) feeds HoverIntent's
// pass-through rule; the event kind lets `DragDetector` see other apps' file drags (R1 §5.1). While the pointer cannot
// change anything (one display, and it shows no panel or its panel is hidden by lock, sleep or In full-screen apps ▸
// Hide), the coordinator pauses it: no move or drag reaches the app then (a game's 1000 Hz mouse included; a paused tap
// is disabled), only mouse-downs (`pause(onPress:)`).
import AppKit
import CoreFoundation
import CrannyCore
import Foundation
import os

private let log = Log.logger(.overlay)

@MainActor final class PointerMonitor {
    /// What the pointer did.
    nonisolated enum Kind: Equatable, Sendable {
        case moved
        /// A mouse button is down and the pointer moves (a drag, possibly another app's file drag).
        case dragged
        /// The left button went up (a drag ends).
        case up
    }

    /// Where the events come from.
    enum Backend: Equatable {
        /// The listen-only event tap (`PointerTap`).
        case tap
        /// NSEvent global and local monitors.
        case monitors
    }

    /// The tap's window-server calls; nil = NSEvent monitors only.
    private let tapSystem: PointerTap.System?
    /// The tap while it is the backend.
    private(set) var tap: PointerTap?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// The press monitors beside the tap, or while paused.
    private var pressGlobal: Any?
    private var pressLocal: Any?
    /// The monitors' speed measurement (the tap keeps its own on its thread).
    private var speed = PointerSpeed()
    private var handler: (CGPoint, Kind) -> Void = { _, _ in }
    private var gate: () -> PointerGate = { PointerGate() }
    /// The gate changed since the tap last had it (published after the events being handled, or the next ones).
    private var gateIsStale = true
    /// Events are being handled: a gate change waits for the publish that follows them.
    private var isHandling = false
    /// The kinds a hop takes from the tap (its storage reused).
    private var hopBuffer: [Kind] = []
    private var onPress: () -> Void = {}
    private var loggedFallback = false
    /// Moves and drags are not reported (`pause(onPress:)`), until `resume()`.
    private(set) var isPaused = false

    /// `tapSystem` nil: never a tap (tests that drive the NSEvent backend).
    init(tapSystem: PointerTap.System? = .live) {
        self.tapSystem = tapSystem
        hopBuffer.reserveCapacity(TapQueue.capacity)
    }

    /// The backend in use; nil before `start`.
    var backend: Backend? {
        if tap != nil { return .tap }
        return globalMonitor != nil || localMonitor != nil || isPaused ? .monitors : nil
    }

    /// Whether a drag being reported can still be under way: always for a monitor's event (handled as it arrives); for
    /// the tap's, only while a mouse button is down. A hop waits out our own event-tracking loops, so it reports their
    /// drags (a Tray tile's drag session, a control) after the button came up, events the NSEvent monitors never see:
    /// the drag detector does not inspect the drag pasteboard for them (our own drags are no file drags, `DropRouter`).
    var dragMayBeLive: Bool { tap == nil || NSEvent.pressedMouseButtons != 0 }

    /// Pointer speed in pt/s from the two most recent events. A pointer that has not moved for 50 ms is at rest.
    var currentSpeed: CGFloat {
        let now = ProcessInfo.processInfo.systemUptime
        return tap?.currentSpeed(now: now) ?? speed.current(now: now)
    }

    /// Starts reporting. `gate` tells the tap which events can matter (`PointerGate`); it is read after the events that
    /// follow a `gateChanged()`, never for an NSEvent backend.
    func start(gate: @escaping () -> PointerGate = { PointerGate() }, _ handler: @escaping (CGPoint, Kind) -> Void) {
        stop()
        self.handler = handler
        self.gate = gate
        if let tapSystem, let tap = PointerTap.make(system: tapSystem, gate: gate(), deliver: Self.hop(to: self)) {
            self.tap = tap
            gateIsStale = false
            installPressMonitors()
            log.info("pointer: listen-only event tap")
        } else {
            installTracking()
            log.info("pointer: NSEvent monitors (no event tap without Input Monitoring or Accessibility)")
        }
        let now = ProcessInfo.processInfo.systemUptime
        isHandling = true
        report(.moved, at: NSEvent.mouseLocation, time: now)               // a pointer already resting on the notch
        isHandling = false
        publishGateIfStale()
    }

    func stop() {
        tap?.stop()
        tap = nil
        removeMonitors()
        removePressMonitors()
        isPaused = false
        onPress = {}
    }

    /// What `gate` returns changed. The tap forwards every event until it has the new gate: published right after the
    /// events being handled, else after the next hop (which this change makes the next event take).
    func gateChanged() {
        gateIsStale = true
        guard !isHandling, !isPaused else { return }
        tap?.invalidate()
    }

    /// Stops reporting moves and drags; only mouse-downs reach `onPress` (a drag may begin while paused, and
    /// `DragDetector` keeps its baseline by them). Call it right after a plain move, when no drag is in progress.
    func pause(onPress: @escaping () -> Void) {
        guard !isPaused, tap != nil || globalMonitor != nil || localMonitor != nil else { return }
        isPaused = true
        self.onPress = onPress
        if let tap {
            tap.setPaused(true)                                                 // the press monitors stay
        } else {
            removeMonitors()
            installPressMonitors()
        }
    }

    /// Reports moves and drags again, from the next event on: nothing is reported now, so the panels learn where the
    /// pointer is when it next moves, as they would have without the pause. The speed is measured from here.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        onPress = {}
        let point = NSEvent.mouseLocation, now = ProcessInfo.processInfo.systemUptime
        gateIsStale = true
        if let tap {
            tap.setPaused(false, at: point, time: now)
            if tap.isAlive() { publishGateIfStale() } else { fallBackToMonitors() }   // the displays may have changed
            speed.rest(at: point, time: now)
            return
        }
        removePressMonitors()
        installTracking()
        speed.rest(at: point, time: now)
    }

    nonisolated static func kind(of type: NSEvent.EventType) -> Kind {
        switch type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: .dragged
        case .leftMouseUp: .up
        default: .moved
        }
    }

    // MARK: NSEvent monitors

    private func installTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp]
        // Monitors run on the main thread (AppKit delivers events there).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let time = event.timestamp, kind = Self.kind(of: event.type)
            MainActor.assumeIsolated { self?.moved(at: time, kind: kind) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.moved(at: event.timestamp, kind: Self.kind(of: event.type))
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }

    /// Mouse-downs: `onPress` while paused, else the tap's check.
    private func installPressMonitors() {
        guard pressGlobal == nil, pressLocal == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Monitors run on the main thread (AppKit delivers events there).
        pressGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.pressed() }
        }
        pressLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.pressed()
            return event
        }
    }

    private func removePressMonitors() {
        if let pressGlobal { NSEvent.removeMonitor(pressGlobal) }
        if let pressLocal { NSEvent.removeMonitor(pressLocal) }
        pressGlobal = nil; pressLocal = nil
    }

    /// A monitor's event: read the pointer now.
    private func moved(at time: TimeInterval, kind: Kind) {
        report(kind, at: NSEvent.mouseLocation, time: time)
    }

    private func report(_ kind: Kind, at point: CGPoint, time: TimeInterval) {
        if let tap { tap.record(point, at: time) } else { speed.record(point, at: time) }
        handler(point, kind)
    }

    /// A mouse-down (the press monitors; tests press here).
    func pressed() {
        if isPaused {
            onPress()
        } else if let tap, !tap.isAlive() {
            fallBackToMonitors()
        }
    }

    // MARK: Tap

    /// The tap stopped receiving events (its grant was revoked): the NSEvent monitors take over at once.
    private func fallBackToMonitors() {
        guard let tap else { return }
        speed = tap.speed
        tap.stop()
        self.tap = nil
        if isPaused {
            installPressMonitors()
        } else {
            removePressMonitors()
            installTracking()
        }
        guard !loggedFallback else { return }
        loggedFallback = true
        log.error("pointer: the event tap stopped (permission revoked?); NSEvent monitors from now on")
    }

    /// A hop from the tap: report the kinds that waited, then publish the gate if they changed it. A tap macOS disabled
    /// for good (`PointerTap.takeStayedDisabled`) hands over to the NSEvent monitors instead.
    private func handleTapEvents() {
        guard let tap else { return }
        if tap.takeStayedDisabled(), !isPaused, !tap.isAlive() {               // paused: `resume` checks it
            fallBackToMonitors()
            return
        }
        tap.take(into: &hopBuffer)
        defer { hopBuffer.removeAll(keepingCapacity: true) }
        isHandling = true
        for kind in hopBuffer {
            guard !isPaused, self.tap === tap else { break }
            handler(NSEvent.mouseLocation, kind)
        }
        isHandling = false
        publishGateIfStale()
    }

    private func publishGateIfStale() {
        guard gateIsStale, !isPaused, let tap else { return }
        gateIsStale = false
        tap.publish(gate())
    }

    /// The run-loop modes a hop runs in: the default and modal-panel modes, the ones in which AppKit hands events to
    /// NSEvent monitors. Not event tracking: while a menu, a control or a window drag tracks, the hop waits.
    private nonisolated(unsafe) static let hopModes = [CFRunLoopMode.defaultMode.rawValue,
                                                       RunLoop.Mode.modalPanel.rawValue as CFString] as CFArray

    /// What the tap calls (on its thread) when events wait: one block on the main run loop takes them all.
    private nonisolated static func hop(to monitor: PointerMonitor) -> @Sendable () -> Void {
        { [weak monitor] in
            let main = CFRunLoopGetMain()
            CFRunLoopPerformBlock(main, hopModes) {
                MainActor.assumeIsolated { monitor?.handleTapEvents() }        // the main run loop runs it
            }
            CFRunLoopWakeUp(main)
        }
    }
}
