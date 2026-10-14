// CrannySystemActivities/Power/PowerObserver.swift — power-source change notifications, no polling (§9.2).
//
// Two IOPS subscriptions, so a Mac on power is not woken for nothing. The limited-power one
// (`IOPSCreateLimitedPowerNotification`, posted only when the Mac switches between AC and battery or UPS power)
// stays attached from `start` to `stop`. The any-source one (`IOPSNotificationCreateRunLoopSource`, posted on
// every change of any attribute of any source: percent, time remaining, accessory batteries — every 60 s on AC,
// measured) is attached only while `PowerModel` follows the details (`setFollowsDetail`). On a switch both fire.
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
    /// true: also every change of any power source (percent, estimates, accessory batteries); false: only the
    /// switches between AC and limited power, and Low Power Mode. Ignored while stopped.
    func setFollowsDetail(_ on: Bool)
    func stop()
}

@MainActor final class PowerObserver: PowerChangeObserving {
    /// AC ↔ battery / UPS switches: attached from `start` to `stop`.
    private var switchSource: CFRunLoopSource?
    /// Any change of any power source: attached only while the details are followed.
    private var detailSource: CFRunLoopSource?
    private var context: Unmanaged<CallbackBox>?
    private var lowPowerObserver: (any NSObjectProtocol)?

    /// The any-source subscription is attached (tests).
    var isFollowingDetail: Bool { detailSource != nil }

    /// The C callback cannot capture: it reaches the handler through this box (both sources' context pointer).
    private final class CallbackBox {
        let fire: @MainActor () -> Void
        init(_ fire: @escaping @MainActor () -> Void) { self.fire = fire }
    }

    /// Both sources' C callback. It runs on the main thread: the sources are on the main run loop.
    private nonisolated static let callback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { box.fire() }          // the sources run on the main run loop
    }

    func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        let box = Unmanaged.passRetained(CallbackBox(onChange))
        context = box
        switchSource = Self.schedule(IOPSCreateLimitedPowerNotification(Self.callback, box.toOpaque()),
                                     failure: "IOPSCreateLimitedPowerNotification failed: no power-source switch notifications")
        setFollowsDetail(true)
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }                  // queue: .main
        }
    }

    func setFollowsDetail(_ on: Bool) {
        guard let context else { return }
        if on, detailSource == nil {
            detailSource = Self.schedule(IOPSNotificationCreateRunLoopSource(Self.callback, context.toOpaque()),
                                         failure: "IOPSNotificationCreateRunLoopSource failed: no battery change notifications")
        } else if !on, let detailSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), detailSource, .commonModes)
            self.detailSource = nil
        }
    }

    func stop() {
        for source in [switchSource, detailSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        switchSource = nil
        detailSource = nil
        context?.release()                                           // after both sources are gone
        context = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }

    /// Adds a source IOPS created to the main run loop; nil (logged) when IOPS refused to create it.
    private static func schedule(_ created: Unmanaged<CFRunLoopSource>?, failure: String) -> CFRunLoopSource? {
        guard let source = created?.takeRetainedValue() else {
            log.error("\(failure, privacy: .public)")
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return source
    }
}
