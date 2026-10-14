// CrannySystemActivities/Power/PowerObserver.swift — power-source change notifications, no polling (§9.2).
//
// Threading: the IOPS run-loop source is scheduled on the MAIN run loop in common modes (so it also fires
// while a menu tracks), so its C callback runs on the main thread; Low Power Mode changes arrive through
// `NSProcessInfoPowerStateDidChange` on the main queue. Both call `onChange` on the main actor.
import CrannyCore
import Foundation
import IOKit.ps
import os

private let log = Log.logger(.system)

/// Something that reports "the power sources changed" (the live observer, or nothing in tests).
@MainActor protocol PowerChangeObserving: AnyObject {
    func start(_ onChange: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor final class PowerObserver: PowerChangeObserving {
    private var source: CFRunLoopSource?
    private var context: Unmanaged<CallbackBox>?
    private var lowPowerObserver: (any NSObjectProtocol)?

    /// The C callback cannot capture: it reaches the handler through this box (the source's context pointer).
    private final class CallbackBox {
        let fire: @MainActor () -> Void
        init(_ fire: @escaping @MainActor () -> Void) { self.fire = fire }
    }

    func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        let box = Unmanaged.passRetained(CallbackBox(onChange))
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { box.fire() }          // the source runs on the main run loop
        }
        if let created = IOPSNotificationCreateRunLoopSource(callback, box.toOpaque())?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
            context = box
        } else {
            box.release()
            log.error("IOPSNotificationCreateRunLoopSource failed: no battery change notifications")
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }                  // queue: .main
        }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        context?.release()
        context = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }
}
