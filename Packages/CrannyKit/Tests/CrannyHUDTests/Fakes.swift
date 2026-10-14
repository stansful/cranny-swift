// Test doubles for every device the HUD touches. Nothing in this test target changes the real volume,
// brightness or keyboard backlight, installs an event tap or asks for a permission.
import CrannyCore
import Foundation
import os
@testable import CrannyHUD

/// A default output device in memory. `state == nil` = not settable (HDMI).
nonisolated final class FakeVolume: SystemVolume {
    struct Store {
        var state: VolumeState?
        var calls: [String] = []
        var failsWrites = false
    }
    let store: OSAllocatedUnfairLock<Store>

    init(_ state: VolumeState? = VolumeState(level: 0.5, isMuted: false, canMute: true)) {
        store = OSAllocatedUnfairLock(initialState: Store(state: state))
    }

    var state: VolumeState? { store.withLock { $0.state } }
    var calls: [String] { store.withLock { $0.calls } }
    func failWrites() { store.withLock { $0.failsWrites = true } }

    func readState() -> VolumeState? { store.withLock { $0.state } }
    func setLevel(_ level: Double) -> Bool {
        store.withLock { store in
            store.calls.append("level(\(level))")
            guard !store.failsWrites, store.state != nil else { return false }
            store.state?.level = level
            return true
        }
    }
    func setMuted(_ muted: Bool) -> Bool {
        store.withLock { store in
            store.calls.append("muted(\(muted))")
            guard !store.failsWrites, store.state?.canMute == true else { return false }
            store.state?.isMuted = muted
            return true
        }
    }
}

/// Brightness or keyboard backlight in memory. `level == nil` = no controllable device.
nonisolated final class FakeLevel: DisplayBrightness, KeyboardBacklight {
    struct Store {
        var level: Double?
        var writes: [Double] = []
        var failsWrites = false
    }
    let store: OSAllocatedUnfairLock<Store>

    init(_ level: Double?) { store = OSAllocatedUnfairLock(initialState: Store(level: level)) }

    var level: Double? { store.withLock { $0.level } }
    var writes: [Double] { store.withLock { $0.writes } }
    func failWrites() { store.withLock { $0.failsWrites = true } }

    func readLevel() -> Double? { store.withLock { $0.level } }
    func setLevel(_ level: Double) -> Bool {
        store.withLock { store in
            store.writes.append(level)
            guard !store.failsWrites, store.level != nil else { return false }
            store.level = level
            return true
        }
    }
}

/// Records what the handler reports to the main actor.
nonisolated final class SignalRecorder: Sendable {
    private let store = OSAllocatedUnfairLock<[HUDSignal]>(initialState: [])
    var signals: [HUDSignal] { store.withLock { $0 } }
    var updates: [HUDUpdate] { signals.compactMap { if case .changed(let u) = $0 { u } else { nil } } }
    var sink: MediaKeyHandler.Sink { { [store] signal in store.withLock { $0.append(signal) } } }
}

/// An event tap that never touches the window server: it records start/stop and hands out its handler.
nonisolated final class FakeInterceptor: KeyInterceptor {
    struct Store {
        var started = 0
        var stopped = 0
        var startSucceeds = true
    }
    let handler: MediaKeyHandler
    let store: OSAllocatedUnfairLock<Store>

    init(handler: MediaKeyHandler, startSucceeds: Bool) {
        self.handler = handler
        store = OSAllocatedUnfairLock(initialState: Store(startSucceeds: startSucceeds))
    }
    var startCount: Int { store.withLock { $0.started } }
    var stopCount: Int { store.withLock { $0.stopped } }
    func start() -> Bool { store.withLock { $0.started += 1; return $0.startSucceeds } }
    func stop() { store.withLock { $0.stopped += 1 } }
}

/// A volume listener that reports only what the test emits.
nonisolated final class FakeVolumeObserver: VolumeObserving {
    let store = OSAllocatedUnfairLock<(running: Bool, onChange: (@Sendable (VolumeObservation) -> Void)?)>(
        initialState: (false, nil))
    var isRunning: Bool { store.withLock { $0.running } }
    func start(onChange: @escaping @Sendable (VolumeObservation) -> Void) { store.withLock { $0 = (true, onChange) } }
    func stop() { store.withLock { $0 = (false, nil) } }
    func emit(_ observation: VolumeObservation) { store.withLock { $0.onChange }?(observation) }
}

/// Fake hardware plus the interceptors and observers the controller created.
@MainActor final class FakeHardware {
    let volume = FakeVolume()
    let brightness = FakeLevel(0.5)
    let keyboard = FakeLevel(0.5)
    var tapStartSucceeds = true
    private let made = OSAllocatedUnfairLock<(taps: [FakeInterceptor], observers: [FakeVolumeObserver])>(initialState: ([], []))

    var taps: [FakeInterceptor] { made.withLock { $0.taps } }
    var observers: [FakeVolumeObserver] { made.withLock { $0.observers } }

    var hardware: HUDHardware {
        let succeeds = tapStartSucceeds
        return HUDHardware(volume: volume, brightness: brightness, keyboard: keyboard,
                           makeInterceptor: { [made] handler in
                               let tap = FakeInterceptor(handler: handler, startSucceeds: succeeds)
                               made.withLock { $0.taps.append(tap) }
                               return tap
                           },
                           makeVolumeObserver: { [made] in
                               let observer = FakeVolumeObserver()
                               made.withLock { $0.observers.append(observer) }
                               return observer
                           })
    }
}

/// Polls `condition` on the main actor until it holds, for at most `timeout` worth of 10-ms polls. Polls are
/// counted, not timed: a render test can hold the main actor for seconds, and the hops a condition waits for
/// (signals and observation callbacks are `Task`s on the main actor) only run between polls.
@MainActor func eventually(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let polls = Int(timeout / .milliseconds(10))
    for _ in 0..<polls {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

extension HUDTapConfig {
    /// Everything on and presentable.
    static let all = HUDTapConfig(isReplacing: true, handlesVolume: true, handlesBrightness: true,
                                  handlesKeyboardBacklight: true, isPresentable: true)
}
