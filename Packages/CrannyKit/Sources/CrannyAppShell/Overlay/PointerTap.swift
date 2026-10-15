// CrannyAppShell/Overlay/PointerTap.swift — the pointer as a listen-only event tap (ARCHITECTURE.md §5.5, §9.2).
// A session tap for mouse moves, drags and left-button ups. Created on the main actor (so `PointerMonitor` knows at
// once whether it runs), it is attached to its own thread's CFRunLoop (user-interactive QoS: hover must feel instant),
// where its callback runs. The tap thread measures the speed from every event and decides which events the main actor
// needs (`PointerGate`): a move or drag far from every panel, on the display the main actor already knows, wakes
// nothing else. The main actor publishes the gate after each change of what it reads (`PointerMonitor.gateChanged`);
// until it has, every event goes through. Forwarded events wait for one hop to the main run loop (`TapQueue`), which
// runs in the default and modal-panel modes only: not while a menu, a control or a window drag tracks, when NSEvent
// monitors see nothing either.
//
// macOS 27 enables a listen-only mouse tap only in a process with Input Monitoring or Accessibility (without either it
// is created and stays disabled). The tap is created only when a silent check finds one of them, and `PointerMonitor`
// uses it only when it is enabled right after creation; nothing asks for either permission, and otherwise the NSEvent
// monitors stay. The callback re-enables a tap macOS disabled (timeout, user input) and reports one that stays
// disabled (`takeStayedDisabled`); `isAlive()` tells the monitor whether it still runs (a revoked grant), checked on
// every mouse-down as well.
import AppKit
import ApplicationServices
import CoreGraphics
import CrannyCore
import Foundation
import os

// MARK: - Gate (pure)

/// What the tap thread knows of the panels, published by the main actor (`OverlayCoordinator.pointerGate()`), and which
/// events the main actor must hear about. Pure, tested.
nonisolated struct PointerGate: Equatable, Sendable {
    /// Every display's frame (AppKit coordinates), in the coordinator's order (`OverlayCoordinator.screens`).
    var screens: [CGRect] = []
    /// The top of the primary display: CG coordinates (top-left origin of the primary display) become AppKit's with it.
    var primaryTop: CGFloat = 0
    /// The display the main actor holds as the pointer's (an index into `screens`), nil when none.
    var pointerScreen: Int?
    /// Where a move can change some panel's hover: its hover or exit zone (satellite included), its menu-bar band (the
    /// courtesy strips lie in it) and a menu's region (`HoverZones`).
    var moveRects: [CGRect] = []
    /// Where a drag can as well: the panels' drag zones (the drag detector's inspection, a file drag's catch).
    var dragRects: [CGRect] = []
    /// Every event matters: a panel has the pointer inside, in its band or in a menu's region; a file drag is in
    /// progress; a display change waits for its rebuild; or the main actor has not published since a change.
    var forwardAll = true

    /// Adds one panel: its zones (nil while hidden: nothing to enter) and where its hover stands (`PanelHover`).
    mutating func addPanel(zones: HoverZones?, inside: Bool, band: BandPosition, lingers: Bool) {
        if inside || band != .outside || lingers { forwardAll = true }
        guard let zones else { return }
        moveRects.append(zones.hoverZone)
        moveRects.append(zones.bandRect)
        if zones.expanded, let region = zones.menuRegion { moveRects.append(region) }
        dragRects.append(zones.dragZone)
    }

    /// `location` (CG coordinates, as the event carries it) in AppKit coordinates, as `NSEvent.mouseLocation` reads it.
    func appKitPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x, y: primaryTop - location.y)
    }

    /// The display under `point` as `OverlayCoordinator.updatePointerDisplay` finds it (its top row included).
    func screenIndex(of point: CGPoint) -> Int? {
        screens.firstIndex { point.x >= $0.minX && point.x < $0.maxX && point.y >= $0.minY && point.y <= $0.maxY }
    }

    /// Whether the main actor must hear about an event of `kind` at `point` that follows one of `previous` kind: every
    /// up and every change between moving and dragging (the drag detector counts drags and settles its baseline at their
    /// end), a display change, and any event where a panel's hover or drag state can change.
    func forwards(_ kind: PointerMonitor.Kind, at point: CGPoint, after previous: PointerMonitor.Kind) -> Bool {
        if forwardAll || kind == .up || (kind == .dragged) != (previous == .dragged) { return true }
        if let screen = screenIndex(of: point), screen != pointerScreen { return true }
        if moveRects.contains(where: { $0.contains(point) }) { return true }
        return kind == .dragged && dragRects.contains { $0.contains(point) }
    }
}

// MARK: - Queue and relay (pure)

/// The events waiting for the main actor's next hop. Only their kinds travel: the main actor reads where the pointer is
/// when the hop runs (`NSEvent.mouseLocation`, as for a monitor's event), so a kind repeated at the end is kept once;
/// a change of kind is kept (the drag detector counts drags and their ends), and so is every up. Pure, tested.
nonisolated struct TapQueue: Equatable, Sendable {
    /// A main actor stalled through this many changes of kind keeps the newest ones.
    static let capacity = 32
    private(set) var kinds: [PointerMonitor.Kind] = []

    init() { kinds.reserveCapacity(Self.capacity) }

    mutating func add(_ kind: PointerMonitor.Kind) {
        if kind != .up, kinds.last == kind { return }
        if kinds.count == Self.capacity { kinds.removeFirst() }
        kinds.append(kind)
    }

    /// Hands the waiting kinds to `buffer` (emptied, its storage kept) and keeps `buffer`'s storage: no allocation.
    mutating func take(into buffer: inout [PointerMonitor.Kind]) {
        buffer.removeAll(keepingCapacity: true)
        swap(&kinds, &buffer)
    }

    mutating func removeAll() { kinds.removeAll(keepingCapacity: true) }
}

/// Pointer speed in pt/s from the two most recent events (HoverIntent's pass-through rule). A pointer that has not moved
/// for 50 ms is at rest. Pure.
nonisolated struct PointerSpeed: Equatable, Sendable {
    private(set) var lastPoint: CGPoint?
    private(set) var lastTime: TimeInterval = 0
    private(set) var speed: CGFloat = 0

    mutating func record(_ point: CGPoint, at time: TimeInterval) {
        if let lastPoint, time > lastTime {
            speed = hypot(point.x - lastPoint.x, point.y - lastPoint.y) / CGFloat(time - lastTime)
        }
        lastPoint = point
        lastTime = time
    }

    /// Measured from here on, from rest.
    mutating func rest(at point: CGPoint, time: TimeInterval) {
        lastPoint = point
        lastTime = time
        speed = 0
    }

    func current(now: TimeInterval) -> CGFloat {
        guard lastPoint != nil, now - lastTime < 0.05 else { return 0 }
        return speed
    }
}

/// The tap thread's bookkeeping between the window server and the main actor; `PointerTap` keeps it behind its lock.
/// Every event updates the speed and goes through the gate; the newest event the gate held back is kept, so a gate that
/// changes (`invalidate`, `publish`) still forwards it when it would now: an event that raced the main actor's change is
/// judged by the new gate, as a monitor's event would have been. Pure, tested.
nonisolated struct PointerRelay: Sendable {
    private(set) var gate = PointerGate()
    private(set) var queue = TapQueue()
    /// A hop to the main actor is on its way (it takes the queue).
    private(set) var hopScheduled = false
    private(set) var speed = PointerSpeed()
    private(set) var isPaused = false
    private var previous: PointerMonitor.Kind = .moved
    private var heldBack: (point: CGPoint, kind: PointerMonitor.Kind)?

    /// An event at `location` (CG coordinates) at `time` (seconds since boot); true when it needs a new hop.
    mutating func received(_ kind: PointerMonitor.Kind, at location: CGPoint, time: TimeInterval) -> Bool {
        guard !isPaused else { return false }
        let point = gate.appKitPoint(location)
        speed.record(point, at: time)
        defer { previous = kind }
        guard gate.forwards(kind, at: point, after: previous) else {
            heldBack = (point, kind)
            return false
        }
        return forward(kind)
    }

    /// What the gate reads changed on the main actor, which publishes again only at its next hop: until then every event
    /// goes through, the newest one held back included. True when that needs a new hop.
    mutating func invalidate() -> Bool {
        gate.forwardAll = true
        guard !isPaused, let held = heldBack else { return false }
        return forward(held.kind)
    }

    /// The main actor's gate after a change; the newest event held back goes through if this gate wants it. True when
    /// that needs a new hop.
    mutating func publish(_ gate: PointerGate) -> Bool {
        self.gate = gate
        guard !isPaused, let held = heldBack, gate.forwards(held.kind, at: held.point, after: held.kind) else { return false }
        return forward(held.kind)
    }

    /// The hop runs: the waiting kinds move to `buffer`.
    mutating func take(into buffer: inout [PointerMonitor.Kind]) {
        hopScheduled = false
        queue.take(into: &buffer)
    }

    /// Nothing is reported until `resume`; what waits is dropped (`PointerMonitor.pause`).
    mutating func pause() {
        isPaused = true
        heldBack = nil
        queue.removeAll()
    }

    /// Reports again from the next event, every one until the main actor publishes; the speed is measured from here.
    mutating func resume(at point: CGPoint, time: TimeInterval) {
        isPaused = false
        gate.forwardAll = true
        previous = .moved
        speed.rest(at: point, time: time)
    }

    /// The main actor reported a position itself (`PointerMonitor.start`).
    mutating func record(_ point: CGPoint, at time: TimeInterval) {
        speed.record(point, at: time)
    }

    private mutating func forward(_ kind: PointerMonitor.Kind) -> Bool {
        heldBack = nil
        queue.add(kind)
        guard !hopScheduled else { return false }
        hopScheduled = true
        return true
    }
}

// MARK: - Tap

/// The listen-only tap and its thread. Created by `PointerMonitor` (`make`), which owns it until `stop()`.
nonisolated final class PointerTap: Sendable {
    /// The window-server calls the tap makes; tests stand in for them.
    struct System: Sendable {
        /// A listen-only session tap for `mask` that calls `callback` with `userInfo`, or nil.
        var create: @Sendable (_ mask: CGEventMask, _ callback: CGEventTapCallBack, _ userInfo: UnsafeMutableRawPointer?) -> CFMachPort?
        var isEnabled: @Sendable (CFMachPort) -> Bool
        var setEnabled: @Sendable (CFMachPort, Bool) -> Void

        /// Creates a tap only when the process has Input Monitoring or Accessibility (both checks are silent), so
        /// nothing here can make macOS ask for either.
        static let live = System(
            create: { mask, callback, userInfo in
                guard CGPreflightListenEventAccess() || AXIsProcessTrusted() else { return nil }
                return CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                         eventsOfInterest: mask, callback: callback, userInfo: userInfo)
            },
            isEnabled: { CGEvent.tapIsEnabled(tap: $0) },
            setEnabled: { CGEvent.tapEnable(tap: $0, enable: $1) })
    }

    /// The events `PointerMonitor`'s NSEvent monitors watch: moves, the three buttons' drags, the left button's up.
    static let mask: CGEventMask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseUp].reduce(0) { $0 | CGEventMask(1) << CGEventMask($1.rawValue) }

    private struct Shared {
        var relay = PointerRelay()
        var port: CFMachPort?
        var runLoop: CFRunLoop?
        /// Bumped by `install` and `stop`, so a thread that starts late never attaches a stopped tap's port.
        var generation = 0
        /// macOS disabled the tap and it stayed disabled when enabled again (`reenable`): the main actor checks it at
        /// its next hop (`takeStayedDisabled`).
        var stayedDisabled = false
    }

    private let system: System
    /// Schedules the main actor's hop (`PointerMonitor`); called on the tap thread, or on the main actor after a change.
    private let deliver: @Sendable () -> Void
    // CFMachPort / CFRunLoop are thread-safe CF objects; the lock orders the relay, start, stop and the thread's setup.
    private let shared = OSAllocatedUnfairLock(uncheckedState: Shared())

    private init(system: System, deliver: @escaping @Sendable () -> Void) {
        self.system = system
        self.deliver = deliver
    }

    /// A running tap that starts from `gate`, or nil when macOS gives none or keeps it disabled (no Input Monitoring,
    /// no Accessibility).
    static func make(system: System, gate: PointerGate, deliver: @escaping @Sendable () -> Void) -> PointerTap? {
        let tap = PointerTap(system: system, deliver: deliver)
        return tap.install(gate: gate) ? tap : nil
    }

    private func install(gate: PointerGate) -> Bool {
        guard let port = system.create(Self.mask, Self.callback, Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        guard system.isEnabled(port) else {
            system.setEnabled(port, false)
            CFMachPortInvalidate(port)
            return false
        }
        let generation = shared.withLockUnchecked { state -> Int in
            _ = state.relay.publish(gate)                                       // nothing waits yet
            state.generation += 1
            state.port = port
            state.runLoop = nil
            return state.generation
        }
        // The thread keeps `self` alive until its run loop exits, so the callback's unretained pointer stays valid.
        let thread = Thread { [self] in runTapLoop(generation: generation) }
        thread.name = "Cranny.PointerTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        let (port, runLoop) = shared.withLockUnchecked { state -> (CFMachPort?, CFRunLoop?) in
            state.generation += 1
            defer { state.port = nil; state.runLoop = nil }
            return (state.port, state.runLoop)
        }
        guard let port else { return }
        system.setEnabled(port, false)
        CFMachPortInvalidate(port)
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    /// Whether the tap still receives events: enabled, or enabled again now (macOS disables a tap on a timeout, and the
    /// callback may not have re-enabled it yet). False once the grant behind it is gone.
    func isAlive() -> Bool {
        guard let port = shared.withLockUnchecked({ $0.port }) else { return false }
        if system.isEnabled(port) { return true }
        system.setEnabled(port, true)
        return system.isEnabled(port)
    }

    /// While paused the window server stops routing pointer events to the tap at all. Switched under the lock, so a
    /// re-enable after a timeout (`reenable`) never turns a paused tap back on.
    func setPaused(_ paused: Bool, at point: CGPoint = .zero, time: TimeInterval = 0) {
        let system = system
        shared.withLockUnchecked { state in
            if paused { state.relay.pause() } else { state.relay.resume(at: point, time: time) }
            if let port = state.port { system.setEnabled(port, !paused) }
        }
    }

    /// `PointerRelay.invalidate`, scheduling the hop it needs.
    func invalidate() {
        if shared.withLockUnchecked({ $0.relay.invalidate() }) { deliver() }
    }

    /// `PointerRelay.publish`, scheduling the hop it needs.
    func publish(_ gate: PointerGate) {
        if shared.withLockUnchecked({ $0.relay.publish(gate) }) { deliver() }
    }

    /// The hop runs (main actor): the waiting kinds move to `buffer`.
    func take(into buffer: inout [PointerMonitor.Kind]) {
        shared.withLockUnchecked { $0.relay.take(into: &buffer) }
    }

    /// The main actor reported a position itself.
    func record(_ point: CGPoint, at time: TimeInterval) {
        shared.withLockUnchecked { $0.relay.record(point, at: time) }
    }

    func currentSpeed(now: TimeInterval) -> CGFloat {
        shared.withLockUnchecked { $0.relay.speed.current(now: now) }
    }

    /// The speed measurement, for the NSEvent monitors that take over (`PointerMonitor`).
    var speed: PointerSpeed { shared.withLockUnchecked { $0.relay.speed } }

    // MARK: Tap thread

    /// The thread's body: attach the port to this thread's run loop and run it until `stop()`.
    private func runTapLoop(generation: Int) {
        let current = CFRunLoopGetCurrent()
        let port = shared.withLockUnchecked { state -> CFMachPort? in
            guard state.generation == generation, let port = state.port else { return nil }   // stopped meanwhile
            state.runLoop = current
            return port
        }
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return }
        CFRunLoopAddSource(current, source, .commonModes)
        CFRunLoopRun()
        CFRunLoopRemoveSource(current, source, .commonModes)
    }

    /// The callback's body for one event (tests hand it events of their own).
    func received(_ type: CGEventType, location: CGPoint, timestamp: CGEventTimestamp) {
        let kind: PointerMonitor.Kind
        switch type {
        case .mouseMoved: kind = .moved
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: kind = .dragged
        case .leftMouseUp: kind = .up
        case .tapDisabledByTimeout, .tapDisabledByUserInput: reenable(); return
        default: return
        }
        // CG timestamps are nanoseconds since boot, NSEvent's `timestamp` (and `systemUptime`) the same in seconds.
        let time = TimeInterval(timestamp) / 1_000_000_000
        if shared.withLockUnchecked({ $0.relay.received(kind, at: location, time: time) }) { deliver() }
    }

    /// macOS disabled the tap (a slow callback, user input): on again unless paused on purpose. A tap that stays
    /// disabled (its grant was revoked) is reported to the main actor at once, which hands over to the NSEvent monitors.
    private func reenable() {
        let system = system
        let enabled = shared.withLockUnchecked { state -> Bool? in
            guard !state.relay.isPaused, let port = state.port else { return nil }
            system.setEnabled(port, true)
            if system.isEnabled(port) { return true }
            state.stayedDisabled = true
            return false
        }
        switch enabled {
        case true?: log.info("pointer tap re-enabled after macOS disabled it")
        case false?: deliver()
        case nil: break
        }
    }

    /// The main actor's hop: true once after macOS disabled the tap and it stayed disabled (`reenable`).
    func takeStayedDisabled() -> Bool {
        shared.withLockUnchecked { state in
            defer { state.stayedDisabled = false }
            return state.stayedDisabled
        }
    }

    /// Runs on the tap thread for every pointer event. Keep it fast: no allocation, one lock.
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        if let userInfo {
            let tap = Unmanaged<PointerTap>.fromOpaque(userInfo).takeUnretainedValue()
            tap.received(type, location: event.location, timestamp: event.timestamp)
        }
        return Unmanaged.passUnretained(event)
    }
}

private nonisolated let log = Log.logger(.overlay)
