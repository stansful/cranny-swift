// CrannyAppShell/Input/TrackpadDetector.swift — "is there a trackpad?" for `SystemEnvironment.hasTrackpad`
// (onboarding's gesture step, haptics copy). Reads the IORegistry for Apple multitouch trackpad drivers (built-in and
// Magic Trackpad); it never opens a HID device, so it needs no Input Monitoring permission. Hot-plug arrives through
// IOKit matching notifications on the main run loop: event-driven, no polling.
import Foundation
import IOKit

@MainActor final class TrackpadDetector {
    /// IOKit classes of Apple's multitouch trackpad drivers (built-in on Apple silicon and Intel, Magic Trackpad).
    nonisolated static let driverClasses = ["AppleMultitouchTrackpadHIDEventDriver", "AppleUSBMultitouchDriver", "BNBTrackpadDevice"]

    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var onChange: (Bool) -> Void = { _ in }
    /// Target of the C notification callback (which cannot capture context).
    private static weak var current: TrackpadDetector?

    /// Whether a trackpad is connected right now.
    nonisolated static func isTrackpadPresent() -> Bool {
        driverClasses.contains { name in
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return false }
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return false }
            IOObjectRelease(service)
            return true
        }
    }

    /// Calls `onChange` with the new presence whenever a trackpad appears or goes away.
    func start(_ onChange: @escaping (Bool) -> Void) {
        stop()
        self.onChange = onChange
        Self.current = self
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        for name in Self.driverClasses {
            for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                let status = IOServiceAddMatchingNotification(port, type, IOServiceMatching(name), { _, iterator in
                    TrackpadDetector.drain(iterator)
                    // Delivered on the main run loop (the port's source is added there).
                    MainActor.assumeIsolated { TrackpadDetector.current?.changed() }
                }, nil, &iterator)
                guard status == KERN_SUCCESS else { continue }
                Self.drain(iterator)                                             // arms the notification
                iterators.append(iterator)
            }
        }
    }

    func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func changed() { onChange(Self.isTrackpadPresent()) }

    /// A matching notification stays armed only after its iterator has been emptied.
    nonisolated private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }
}
