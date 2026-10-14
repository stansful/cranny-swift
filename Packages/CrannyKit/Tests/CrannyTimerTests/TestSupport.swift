// Doubles for the timer model: a manual clock, a manual scheduler and a silent sound (no sleeps, no sounds).
import CrannyCore
import Foundation
@testable import CrannyTimer

/// A fixed reference instant: 2026-10-14 12:00:00 UTC.
nonisolated let t0 = Date(timeIntervalSinceReferenceDate: 813_672_000)

@MainActor final class ManualClock {
    var now: Date
    init(_ now: Date = t0) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor final class ManualScheduler: TimerWakeScheduling {
    private(set) var date: Date?
    private var action: (@MainActor () -> Void)?
    private(set) var cancels = 0
    func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) { self.date = date; self.action = action }
    func cancel() { date = nil; action = nil; cancels += 1 }
    /// Advances `clock` to the pending wake-up and runs it (what the real scheduler does after its sleep).
    func fire(advancing clock: ManualClock) {
        guard let date, let action else { return }
        if date > clock.now { clock.now = date }
        self.date = nil
        self.action = nil
        action()
    }
}

@MainActor struct TimerHarness {
    let clock = ManualClock()
    let scheduler = ManualScheduler()
    let sound = SilentTimerSound()
    let services = CrannyServices.preview()
    let peekLog = PeekLog()
    let demo = DemoFlag()
    let model: TimerModel

    init(file: TimerStateFile? = nil) {
        let clock = self.clock, peekLog = self.peekLog, demo = self.demo
        model = TimerModel(settings: services.settings, dependencies: TimerDependencies(
            now: { clock.now }, scheduler: scheduler, sound: sound, file: file,
            isDemoMode: { demo.isOn }, requestPeek: { peekLog.values.append($0) }))
    }
}

@MainActor final class PeekLog { var values: [ActivityID] = [] }
@MainActor final class DemoFlag { var isOn = false }

func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "cranny-timer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "state.json")
}
