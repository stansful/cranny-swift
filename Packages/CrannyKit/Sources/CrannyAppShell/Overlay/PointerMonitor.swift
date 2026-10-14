// CrannyAppShell/Overlay/PointerMonitor.swift — where the pointer is and how fast it moves (ARCHITECTURE.md §5.5).
// Global AND local NSEvent monitors (global monitors miss our own windows); mouse events need no permission.
// The handler is O(displays) and allocation-free. Speed feeds HoverIntent's pass-through rule.
import AppKit
import Foundation

@MainActor final class PointerMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var last: (point: CGPoint, time: TimeInterval)?
    private var speed: CGFloat = 0
    private var handler: (CGPoint) -> Void = { _ in }

    /// Pointer speed in pt/s from the two most recent events. A pointer that has not moved for 50 ms is at rest.
    var currentSpeed: CGFloat {
        guard let last, ProcessInfo.processInfo.systemUptime - last.time < 0.05 else { return 0 }
        return speed
    }

    func start(_ handler: @escaping (CGPoint) -> Void) {
        stop()
        self.handler = handler
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp]
        // Monitors run on the main thread (AppKit delivers events there).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.moved(at: time) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.moved(at: event.timestamp)
            return event
        }
        moved(at: ProcessInfo.processInfo.systemUptime)       // a pointer already resting on the notch
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }

    private func moved(at time: TimeInterval) {
        let point = NSEvent.mouseLocation
        if let last, time > last.time {
            speed = hypot(point.x - last.point.x, point.y - last.point.y) / CGFloat(time - last.time)
        }
        last = (point, time)
        handler(point)
    }
}
