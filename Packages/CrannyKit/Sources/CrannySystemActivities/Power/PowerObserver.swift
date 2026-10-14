// CrannySystemActivities/Power/PowerObserver.swift — power-source change notifications, no polling (§9.2).
//
// Two IOPS subscriptions, so a Mac on power is not woken for nothing. The limited-power one
// (`IOPSCreateLimitedPowerNotification`, notify key `kIOPSNotifyPowerSource`: posted only when the Mac switches
// between AC and battery or UPS power) is on the run loop from `start` to `stop`. The other one
// (`IOPSNotificationCreateRunLoopSource`, notify key `kIOPSTimeRemainingNotificationKey`: posted when the internal
// battery's percent or time remaining changes, so often while charging or discharging, and on a switch) is on the
// run loop only while `PowerModel` follows the details (`setFollowsDetail`). On a switch both fire. (Both keys
// read from IOKit on macOS 27; neither is `kIOPSNotifyAnyPowerSource`, which is posted every 60 s on AC.)
//
// Both sources are created once, at the first `start`, and are only added to and removed from the run loop
// after that: IOPS never frees a source's notify registration, not even when the source is released (measured
// on macOS 27: one mach port per source created), so creating one per change of `setFollowsDetail` would leak a
// live registration each time.
//
// Threading: both IOPS run-loop sources are scheduled on the MAIN run loop in common modes (so they also fire
// while a menu tracks), so their C callback runs on the main thread; Low Power Mode changes arrive through
// `NSProcessInfoPowerStateDidChange` on the main queue. All of them call `onChange` on the main actor.
import CrannyCore
import Foundation
import IOKit.ps
import os

private let log = Log.logger(.system)

/// Something that reports "the power sources changed" (the live observer, or a test double).
@MainActor protocol PowerChangeObserving: AnyObject {
    /// Reports AC ↔ battery switches, Low Power Mode and, until `setFollowsDetail(false)`, every other change.
    /// Calling it again restarts.
    func start(_ onChange: @escaping @MainActor () -> Void)
    /// true: also every change of the battery's percent and time estimates; false: only the switches between AC
    /// and limited power, and Low Power Mode. Ignored while stopped.
    func setFollowsDetail(_ on: Bool)
    func stop()
}

@MainActor final class PowerObserver: PowerChangeObserving {
    /// AC ↔ battery / UPS switches: on the run loop from `start` to `stop`.
    private var switchSource: CFRunLoopSource?
    /// Percent and time-remaining changes: on the run loop only while the details are followed.
    private var detailSource: CFRunLoopSource?
    /// Both sources' context. Never released: IOPS keeps the pointer as long as it keeps the registrations.
    private var context: Unmanaged<CallbackBox>?
    private var lowPowerObserver: (any NSObjectProtocol)?
    private var isRunning = false

    /// The detail subscription is on the run loop (tests).
    private(set) var isFollowingDetail = false
    /// IOPS sources created so far: two at most, whatever `start`, `stop` and `setFollowsDetail` do (tests).
    private(set) var sourcesCreated = 0

    /// The C callback cannot capture: it reaches the handler through this box (both sources' context pointer).
    private final class CallbackBox {
        /// The current `start`'s handler (nil while stopped).
        var fire: (@MainActor () -> Void)?
    }

    /// Both sources' C callback. It runs on the main thread: the sources are on the main run loop.
    private nonisolated static let callback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { box.fire?() }         // the sources run on the main run loop
    }

    func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        let box = context ?? makeSources()
        box.takeUnretainedValue().fire = onChange
        isRunning = true
        if let switchSource { CFRunLoopAddSource(CFRunLoopGetMain(), switchSource, .commonModes) }
        setFollowsDetail(true)
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }                  // queue: .main
        }
    }

    func setFollowsDetail(_ on: Bool) {
        guard isRunning, on != isFollowingDetail, let detailSource else { return }
        if on {
            CFRunLoopAddSource(CFRunLoopGetMain(), detailSource, .commonModes)
        } else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), detailSource, .commonModes)
        }
        isFollowingDetail = on
    }

    func stop() {
        setFollowsDetail(false)
        if isRunning, let switchSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), switchSource, .commonModes) }
        isRunning = false
        context?.takeUnretainedValue().fire = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }

    /// Creates the box and both sources, once (see the top); a source IOPS refuses to create is logged and missing.
    private func makeSources() -> Unmanaged<CallbackBox> {
        let box = Unmanaged.passRetained(CallbackBox())
        context = box
        switchSource = created(IOPSCreateLimitedPowerNotification(Self.callback, box.toOpaque()),
                               failure: "IOPSCreateLimitedPowerNotification failed: no power-source switch notifications")
        detailSource = created(IOPSNotificationCreateRunLoopSource(Self.callback, box.toOpaque()),
                               failure: "IOPSNotificationCreateRunLoopSource failed: no battery change notifications")
        return box
    }

    private func created(_ source: Unmanaged<CFRunLoopSource>?, failure: String) -> CFRunLoopSource? {
        guard let source = source?.takeRetainedValue() else {
            log.error("\(failure, privacy: .public)")
            return nil
        }
        sourcesCreated += 1
        return source
    }
}
