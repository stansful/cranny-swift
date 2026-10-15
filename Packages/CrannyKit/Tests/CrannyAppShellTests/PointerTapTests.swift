// The pointer tap (ARCHITECTURE.md §5.5, §9.2): the gate never keeps from the main actor an event that would change a
// panel's hover, a drag's inspection, the drag detector's baseline or the pointer's display; the queue keeps every
// change of kind; the relay judges an event that raced a change by the new gate; and the monitor picks the tap only
// when macOS enables it, falls back to NSEvent monitors when it stops, and pauses either backend. A stand-in window
// server (`PointerTap.System`) and hand-made events: nothing here needs a permission or moves the pointer.
import AppKit
import CoreGraphics
@testable import CrannyCore
import Foundation
import os
import Testing
@testable import CrannyAppShell

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

/// A closed panel's zones with its wings, as `NotchPanelController` builds them.
private func closedZones() -> HoverZones {
    let layout = NotchLayout(metrics: .reference)
    let panel = CGRect(x: 456, y: 782, width: 600, height: 200)
    let shape = HoverZones.shapeRect(layout.closed, panelFrame: panel)
    return HoverZones(shape: shape, satellite: nil, wings: shape.insetBy(dx: -40, dy: 0), screenFrame: screen,
                      band: layout.band, expanded: false)
}

/// An open panel's zones with a satellite and a menu's region below it.
private func openZones() -> HoverZones {
    var zones = HoverZones(shape: CGRect(x: 456, y: 702, width: 600, height: 280),
                           satellite: CGRect(x: 1070, y: 940, width: 40, height: 32), wings: nil, screenFrame: screen,
                           band: 37, expanded: true)
    zones.menuRegion = CGRect(x: 600, y: 520, width: 220, height: 200)
    return zones
}

private func gate(_ zones: HoverZones?) -> PointerGate {
    var gate = PointerGate(screens: [screen], primaryTop: screen.maxY, pointerScreen: 0, forwardAll: false)
    gate.addPanel(zones: zones, inside: false, band: .outside, lingers: false)
    return gate
}

/// Every 7 pt across the display, a little beyond its edges, and its top row.
private let grid: [CGPoint] = stride(from: -14.0, through: screen.maxX + 14, by: 7).flatMap { x in
    (stride(from: -14.0, through: screen.maxY + 14, by: 7).map { CGPoint(x: x, y: $0) } + [CGPoint(x: x, y: screen.maxY)])
}

// MARK: - Gate

/// From rest (outside, out of the band), a move the gate keeps back changes nothing `HoverTracker` reports, and a drag
/// it keeps back is outside every drag zone (where the detector inspects and a file drag is caught).
@Test func theGateKeepsBackOnlyEventsThatChangeNothing() {
    for zones in [closedZones(), openZones()] {
        let gate = gate(zones)
        for point in grid {
            if !gate.forwards(.moved, at: point, after: .moved) {
                #expect(HoverTracker().update(point, zones: zones).isEmpty, "move at \(point)")
            }
            if !gate.forwards(.dragged, at: point, after: .dragged) {
                #expect(!zones.dragZone.contains(point) && HoverTracker().update(point, zones: zones).isEmpty,
                        "drag at \(point)")
            }
        }
        #expect(!gate.forwards(.moved, at: CGPoint(x: 300, y: 300), after: .moved))        // far below: nothing wakes
        #expect(!gate.forwards(.dragged, at: CGPoint(x: 300, y: 300), after: .dragged))
    }
    // A hidden panel has nothing to enter.
    #expect(!gate(nil).forwards(.moved, at: CGPoint(x: 756, y: 975), after: .moved))
}

/// A move just below the band beside the notch matters only to a drag (the drag zone), not to hover.
@Test func theDragZoneCountsOnlyForDrags() throws {
    let zones = closedZones()
    let point = CGPoint(x: zones.shape.minX - 60, y: screen.maxY - zones.band - 20)
    #expect(zones.dragZone.contains(point) && !zones.hoverZone.contains(point) && !zones.bandRect.contains(point))
    #expect(!gate(zones).forwards(.moved, at: point, after: .moved))
    #expect(gate(zones).forwards(.dragged, at: point, after: .dragged))
}

/// The pointer inside, in a band, in a menu's region, a file drag or an out-of-date gate: every event goes through.
@Test func everyEventGoesThroughWhileAPanelHasThePointer() {
    let far = CGPoint(x: 300, y: 300)
    for (inside, band, lingers) in [(true, BandPosition.outside, false), (false, .band, false), (false, .courtesy, false),
                                    (false, .outside, true)] {
        var gate = PointerGate(screens: [screen], primaryTop: screen.maxY, pointerScreen: 0, forwardAll: false)
        gate.addPanel(zones: closedZones(), inside: inside, band: band, lingers: lingers)
        #expect(gate.forwards(.moved, at: far, after: .moved))
    }
    #expect(PointerGate().forwards(.moved, at: far, after: .moved))                       // nothing published yet
}

/// Every up; the first drag event of a drag (the detector counts it) and the first move after one (its baseline).
@Test func theGateForwardsEveryUpAndEveryChangeBetweenMovingAndDragging() {
    let gate = gate(closedZones()), far = CGPoint(x: 300, y: 300)
    #expect(gate.forwards(.up, at: far, after: .dragged) && gate.forwards(.up, at: far, after: .moved))
    #expect(gate.forwards(.dragged, at: far, after: .moved) && gate.forwards(.dragged, at: far, after: .up))
    #expect(gate.forwards(.moved, at: far, after: .dragged))
    #expect(!gate.forwards(.moved, at: far, after: .up) && !gate.forwards(.dragged, at: far, after: .dragged))
}

/// The display under the pointer is found as the coordinator finds it, and a new one goes through.
@Test func theGateForwardsADisplayChange() {
    let right = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    var gate = PointerGate(screens: [screen, right], primaryTop: screen.maxY, pointerScreen: 0, forwardAll: false)
    #expect(gate.screenIndex(of: CGPoint(x: 10, y: screen.maxY)) == 0)                     // the top row counts
    #expect(gate.screenIndex(of: CGPoint(x: 1512, y: 10)) == 1)                            // the left edge is the right's
    #expect(gate.screenIndex(of: CGPoint(x: 10, y: -5)) == nil)
    #expect(!gate.forwards(.moved, at: CGPoint(x: 300, y: 300), after: .moved))
    #expect(gate.forwards(.moved, at: CGPoint(x: 2000, y: 300), after: .moved))
    gate.pointerScreen = 1
    #expect(!gate.forwards(.moved, at: CGPoint(x: 2000, y: 300), after: .moved))
    #expect(!gate.forwards(.moved, at: CGPoint(x: 10, y: -5), after: .moved))             // on no display: no change
}

/// CG coordinates (top-left of the primary display) become AppKit's as `NSEvent.mouseLocation` reads them.
@Test func tapLocationsBecomeAppKitPoints() {
    let gate = PointerGate(screens: [screen], primaryTop: 982)
    #expect(gate.appKitPoint(CGPoint(x: 938, y: 0)) == CGPoint(x: 938, y: 982))
    #expect(gate.appKitPoint(CGPoint(x: 938, y: 557.96875)) == CGPoint(x: 938, y: 424.03125))
    #expect(gate.appKitPoint(CGPoint(x: 2000, y: 1100)) == CGPoint(x: 2000, y: -118))      // a display below
}

// MARK: - Queue and relay

@Test func theQueueKeepsTheKindsInOrderOnceEach() {
    var queue = TapQueue()
    for kind: PointerMonitor.Kind in [.moved, .moved, .dragged, .dragged, .up, .up, .moved, .dragged, .moved] {
        queue.add(kind)
    }
    #expect(queue.kinds == [.moved, .dragged, .up, .up, .moved, .dragged, .moved])
    var buffer: [PointerMonitor.Kind] = [.up]
    queue.take(into: &buffer)
    #expect(buffer == [.moved, .dragged, .up, .up, .moved, .dragged, .moved] && queue.kinds.isEmpty)
    for index in 0...(TapQueue.capacity + 5) { queue.add(index.isMultiple(of: 2) ? .moved : .dragged) }   // 38 changes
    #expect(queue.kinds.count == TapQueue.capacity && queue.kinds.first == .moved && queue.kinds.last == .dragged)
}

/// One hop for any number of events; an event the gate kept back goes through when the gate changes to want it.
@Test func theRelayHopsOnceAndJudgesARacedEventByTheNewGate() {
    var relay = PointerRelay()
    let zones = closedZones()
    let far = CGPoint(x: 300, y: screen.maxY - 300)                                       // CG: 300 pt below the top
    let notch = CGPoint(x: zones.shape.midX, y: 2)
    var hops: [Bool] = []
    hops.append(relay.received(.moved, at: far, time: 1))                                 // nothing published: through
    hops.append(relay.received(.moved, at: far, time: 1.01))                              // the hop is on its way
    #expect(hops == [true, false] && relay.hopScheduled)
    var buffer: [PointerMonitor.Kind] = []
    relay.take(into: &buffer)
    #expect(buffer == [.moved] && !relay.hopScheduled)

    hops = [relay.publish(gate(zones))]
    hops.append(relay.received(.moved, at: far, time: 1.02))                              // far away: kept back
    hops.append(relay.received(.moved, at: notch, time: 1.03))                            // at the notch: through
    #expect(hops == [false, false, true])
    relay.take(into: &buffer)
    hops = [relay.received(.moved, at: far, time: 1.04)]
    hops.append(relay.invalidate())                                                       // a change: the kept one goes
    #expect(hops == [false, true])
    relay.take(into: &buffer)
    #expect(buffer == [.moved])
    hops = [relay.received(.moved, at: far, time: 1.05)]                                  // and all, until published
    #expect(hops == [true])
    relay.take(into: &buffer)

    hops = [relay.publish(gate(zones)), relay.received(.moved, at: far, time: 1.06)]
    var inside = gate(zones)
    inside.forwardAll = true                                                              // the pointer went inside
    hops.append(relay.publish(inside))                                                    // the raced move goes
    #expect(hops == [false, false, true])
    relay.take(into: &buffer)
    #expect(buffer == [.moved])
}

@Test func theRelayStaysQuietWhilePausedAndMeasuresSpeedFromEventTimes() {
    var relay = PointerRelay()
    var hops = [relay.publish(gate(closedZones()))]
    hops.append(relay.received(.dragged, at: CGPoint(x: 300, y: 300), time: 1))           // a drag begins
    #expect(hops == [false, true])
    relay.pause()
    var buffer: [PointerMonitor.Kind] = []
    relay.take(into: &buffer)
    #expect(buffer.isEmpty)                                                               // dropped by the pause
    hops = [relay.received(.up, at: CGPoint(x: 300, y: 300), time: 1.1), relay.invalidate()]
    #expect(hops == [false, false])
    relay.resume(at: CGPoint(x: 300, y: 682), time: 2)
    #expect(relay.speed.current(now: 2.01) == 0)
    hops = [relay.received(.moved, at: CGPoint(x: 312, y: 300), time: 2.01)]              // every event until published
    #expect(hops == [true])
    #expect(abs(relay.speed.current(now: 2.02) - 1200) < 0.001)                          // 12 pt in 10 ms
    #expect(relay.speed.current(now: 2.07) == 0)                                          // at rest after 50 ms
}

// MARK: - Backend selection

/// A stand-in window server: taps are local mach ports. A tap runs while it is enabled and macOS grants it (Input
/// Monitoring or Accessibility); without the grant enabling it again does nothing.
private nonisolated final class FakeWindowServer: Sendable {
    let granted = OSAllocatedUnfairLock(initialState: true)
    let enabled = OSAllocatedUnfairLock(initialState: true)
    let created = OSAllocatedUnfairLock(initialState: 0)
    let gives: Bool

    init(gives: Bool = true) { self.gives = gives }

    var system: PointerTap.System {
        PointerTap.System(
            create: { [self] _, _, _ in
                guard gives else { return nil }
                created.withLock { $0 += 1 }
                return Self.port()
            },
            isEnabled: { [self] _ in granted.withLock { $0 } && enabled.withLock { $0 } },
            setEnabled: { [self] _, on in enabled.withLock { $0 = on } })
    }

    var isEnabled: Bool { enabled.withLock { $0 } }

    private static let callout: CFMachPortCallBack = { _, _, _, _ in }
    private static func port() -> CFMachPort? {
        var context = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        return CFMachPortCreate(nil, callout, &context, nil)
    }
}

/// Runs the main run loop in `mode` briefly (a hop waits in it).
@MainActor private func spin(_ mode: CFRunLoopMode = .defaultMode) {
    _ = CFRunLoopRunInMode(mode, 0.05, false)
}

@Test func theMonitorUsesTheTapOnlyWhenMacOSEnablesIt() {
    _ = NSApplication.shared
    let none = FakeWindowServer(gives: false)
    let monitor = PointerMonitor(tapSystem: none.system)
    monitor.start { _, _ in }
    #expect(monitor.backend == .monitors)                                                 // no tap at all
    monitor.stop()

    let disabled = FakeWindowServer()
    disabled.granted.withLock { $0 = false }                                             // created, never enabled
    let second = PointerMonitor(tapSystem: disabled.system)
    second.start { _, _ in }
    #expect(second.backend == .monitors && second.tap == nil && disabled.created.withLock { $0 } == 1)
    second.stop()

    let granted = FakeWindowServer()
    let third = PointerMonitor(tapSystem: granted.system)
    var kinds: [PointerMonitor.Kind] = []
    third.start { _, kind in kinds.append(kind) }
    #expect(third.backend == .tap && kinds == [.moved])                                   // the pointer where it rests
    third.stop()
    #expect(third.backend == nil)
    #expect(PointerMonitor(tapSystem: nil).backend == nil)
}

/// Events reach the handler through one main-run-loop hop, not while an event-tracking loop runs (a menu, a control),
/// and those far from every panel never do.
@Test func tapEventsReachTheHandlerInOneHop() throws {
    _ = NSApplication.shared
    let server = FakeWindowServer()
    let monitor = PointerMonitor(tapSystem: server.system)
    var published = gate(closedZones())
    var kinds: [PointerMonitor.Kind] = []
    monitor.start(gate: { published }) { _, kind in kinds.append(kind) }
    defer { monitor.stop() }
    let tap = try #require(monitor.tap)
    kinds.removeAll()
    let ns: (TimeInterval) -> CGEventTimestamp = { CGEventTimestamp($0 * 1_000_000_000) }

    tap.received(.mouseMoved, location: CGPoint(x: 300, y: 600), timestamp: ns(1))         // far: kept back
    spin()
    #expect(kinds.isEmpty)
    tap.received(.leftMouseDragged, location: CGPoint(x: 300, y: 600), timestamp: ns(1.01))
    tap.received(.leftMouseDragged, location: CGPoint(x: 310, y: 600), timestamp: ns(1.02))
    tap.received(.leftMouseUp, location: CGPoint(x: 310, y: 600), timestamp: ns(1.03))
    spin(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
    #expect(kinds.isEmpty)                                                                // a tracking loop: it waits
    spin()
    #expect(kinds == [.dragged, .up])

    kinds.removeAll()
    tap.received(.mouseMoved, location: CGPoint(x: 300, y: 600), timestamp: ns(1.1))
    published.forwardAll = true                                                           // say a panel's state changed
    monitor.gateChanged()
    spin()
    #expect(kinds == [.moved])                                                            // the raced move came through
}

/// A tap that stops (a revoked grant) hands over to the NSEvent monitors at the next press or resume; pausing works on
/// both backends.
@Test func aStoppedTapHandsOverToTheMonitors() throws {
    _ = NSApplication.shared
    let server = FakeWindowServer()
    let monitor = PointerMonitor(tapSystem: server.system)
    var kinds: [PointerMonitor.Kind] = []
    monitor.start { _, kind in kinds.append(kind) }
    defer { monitor.stop() }
    let tap = try #require(monitor.tap)

    var presses = 0
    monitor.pause { presses += 1 }
    #expect(monitor.isPaused && monitor.backend == .tap)
    tap.received(.mouseMoved, location: CGPoint(x: 756, y: 2), timestamp: 1)
    spin()
    monitor.pressed()
    #expect(kinds == [.moved] && presses == 1)                                            // only the press while paused
    monitor.resume()
    #expect(!monitor.isPaused && monitor.backend == .tap && presses == 1)
    monitor.pressed()
    #expect(monitor.backend == .tap)                                                      // still enabled: nothing to do

    server.granted.withLock { $0 = false }                                               // revoked
    monitor.pressed()
    #expect(monitor.backend == .monitors && monitor.tap == nil)
    monitor.pause { presses += 1 }
    monitor.pressed()
    #expect(monitor.isPaused && presses == 2)
    monitor.resume()
    #expect(!monitor.isPaused && monitor.backend == .monitors)

    let other = FakeWindowServer()
    let second = PointerMonitor(tapSystem: other.system)
    second.start { _, _ in }
    defer { second.stop() }
    second.pause {}
    #expect(!other.isEnabled)                                                             // paused: disabled
    other.granted.withLock { $0 = false }
    second.resume()                                                                       // re-enabled, still off
    #expect(second.backend == .monitors)
}

/// macOS disabled the tap (a slow callback): the callback enables it again and the tap stays. A paused tap stays off.
/// One that stays disabled (the grant revoked) hands over at the main actor's next hop, without waiting for a press.
@Test func aTapMacOSDisabledRunsAgainOrHandsOver() throws {
    _ = NSApplication.shared
    let server = FakeWindowServer()
    let monitor = PointerMonitor(tapSystem: server.system)
    monitor.start { _, _ in }
    defer { monitor.stop() }
    let tap = try #require(monitor.tap)

    server.enabled.withLock { $0 = false }                                               // timed out
    tap.received(.tapDisabledByTimeout, location: .zero, timestamp: 0)
    spin()
    #expect(server.isEnabled && monitor.backend == .tap)

    monitor.pause {}
    tap.received(.tapDisabledByUserInput, location: .zero, timestamp: 0)
    #expect(!server.isEnabled)                                                            // off on purpose: stays off
    monitor.resume()
    #expect(server.isEnabled && monitor.backend == .tap)

    server.granted.withLock { $0 = false }                                               // revoked
    server.enabled.withLock { $0 = false }
    tap.received(.tapDisabledByUserInput, location: .zero, timestamp: 0)
    #expect(monitor.backend == .tap)                                                      // decided on the main actor
    spin()
    #expect(monitor.backend == .monitors && monitor.tap == nil)
}

// MARK: - What the gate reads

/// A panel's hover tells the coordinator whenever what the gate reads of it changes (inside, the band, a menu's region
/// lasting), once per change, and never for a move that changes none of it.
@MainActor @Test func thePanelsHoverReportsEachChangeTheGateReads() {
    /// What the closures read, changed by the test.
    @MainActor final class World {
        var zones = HoverZones(shape: CGRect(x: 456, y: 702, width: 600, height: 280), satellite: nil, wings: nil,
                               screenFrame: screen, band: 37, expanded: true)
        var pointer = CGPoint(x: 300, y: 300)
        var changes = 0
    }
    let hover = PanelHover(), world = World()
    hover.zones = { world.zones }
    hover.send = { _ in }
    hover.pointer = { world.pointer }
    hover.after = { _, _ in }
    hover.changed = { world.changes += 1 }
    let moves: [(CGPoint, Int)] = [
        (CGPoint(x: 300, y: 300), 0), (CGPoint(x: 310, y: 320), 0),                       // outside, as before
        (CGPoint(x: 756, y: 900), 1), (CGPoint(x: 760, y: 880), 1),                       // inside
        (CGPoint(x: 756, y: 960), 2),                                                     // inside, in the band
        (CGPoint(x: 300, y: 960), 3),                                                     // left, still in the band
        (CGPoint(x: 300, y: 300), 4),                                                     // out of the band
    ]
    for (point, expected) in moves {
        hover.moved(to: point)
        #expect(world.changes == expected, "move to \(point)")
    }

    let button = CGPoint(x: 756, y: 800), picked = CGPoint(x: 800, y: 650), menu = CGSize(width: 220, height: 160)
    hover.moved(to: button)
    #expect(world.changes == 5)
    hover.menuBegan(at: button)
    #expect(world.changes == 5)
    world.pointer = picked
    hover.menuEnded(at: picked, reach: menu)                                              // the region lasts
    #expect(hover.linger.region != nil && world.changes == 6)
    hover.moved(to: CGPoint(x: 800, y: 640))                                              // still in it
    #expect(world.changes == 6)
    world.zones.expanded = false                                                          // closed: the region ends
    hover.surfaceChanged()
    #expect(hover.linger.region == nil && !hover.isInside && world.changes == 7)
}
