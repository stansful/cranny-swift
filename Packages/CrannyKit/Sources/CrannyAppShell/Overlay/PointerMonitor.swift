// CrannyAppShell/Overlay/PointerMonitor.swift — where the pointer is and how fast it moves (ARCHITECTURE.md §5.5).
// Global AND local NSEvent monitors (global monitors miss our own windows); mouse events need no permission.
// The handler is O(displays) and allocation-free. Speed feeds HoverIntent's pass-through rule; the event kind
// lets `DragDetector` see other apps' file drags (R1 §5.1). While the pointer cannot change anything (one display,
// and it shows no panel or its panel is hidden behind lock, sleep or "Hide everything"), the coordinator pauses it:
// no move or drag reaches the app then (a game's 1000 Hz mouse included), only mouse-downs (`pause(onPress:)`).
import AppKit
import Foundation

@MainActor final class PointerMonitor {
    /// What the pointer did.
    enum Kind: Equatable, Sendable {
        case moved
        /// A mouse button is down and the pointer moves (a drag, possibly another app's file drag).
        case dragged
        /// The left button went up (a drag ends).
        case up
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var last: (point: CGPoint, time: TimeInterval)?
    private var speed: CGFloat = 0
    private var handler: (CGPoint, Kind) -> Void = { _, _ in }
    private var onPress: () -> Void = {}
    /// Moves and drags are not reported (`pause(onPress:)`), until `resume()`.
    private(set) var isPaused = false

    /// Pointer speed in pt/s from the two most recent events. A pointer that has not moved for 50 ms is at rest.
    var currentSpeed: CGFloat {
        guard let last, ProcessInfo.processInfo.systemUptime - last.time < 0.05 else { return 0 }
        return speed
    }

    func start(_ handler: @escaping (CGPoint, Kind) -> Void) {
        stop()
        self.handler = handler
        installTracking()
        moved(at: ProcessInfo.processInfo.systemUptime, kind: .moved)      // a pointer already resting on the notch
    }

    func stop() {
        removeMonitors()
        isPaused = false
    }

    /// Stops reporting moves and drags; only mouse-downs reach `onPress` (a drag may begin while paused, and
    /// `DragDetector` keeps its baseline by them). Call it right after a plain move, when no drag is in progress.
    func pause(onPress: @escaping () -> Void) {
        guard !isPaused, globalMonitor != nil || localMonitor != nil else { return }
        removeMonitors()
        isPaused = true
        self.onPress = onPress
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Monitors run on the main thread (AppKit delivers events there).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.onPress() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.onPress()
            return event
        }
    }

    /// Reports moves and drags again, from the next event on: nothing is reported now, so the panels learn where the
    /// pointer is when it next moves, as they would have without the pause. The speed is measured from here.
    func resume() {
        guard isPaused else { return }
        removeMonitors()
        isPaused = false
        onPress = {}
        installTracking()
        last = (NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime)
        speed = 0
    }

    nonisolated static func kind(of type: NSEvent.EventType) -> Kind {
        switch type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: .dragged
        case .leftMouseUp: .up
        default: .moved
        }
    }

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

    private func moved(at time: TimeInterval, kind: Kind) {
        let point = NSEvent.mouseLocation
        if let last, time > last.time {
            speed = hypot(point.x - last.point.x, point.y - last.point.y) / CGFloat(time - last.time)
        }
        last = (point, time)
        handler(point, kind)
    }
}
