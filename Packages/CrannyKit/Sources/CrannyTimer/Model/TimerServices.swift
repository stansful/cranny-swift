// CrannyTimer/Model/TimerServices.swift — the timer model's side effects behind small protocols, so tests drive it
// with a manual clock, a manual scheduler and a silent sound player (no sleeps, no sounds, no files).
import AppKit
import CrannyCore
import Foundation
import os

private let log = Log.logger(.timer)

// MARK: - One wake-up at a time

/// Calls an action once at a date. Scheduling again replaces the pending wake-up.
@MainActor protocol TimerWakeScheduling: AnyObject {
    func schedule(at date: Date, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

/// One `Task.sleep` to the deadline (ARCHITECTURE.md §9.1 rule 7: sleep to deadlines, never repeating timers).
/// The sleep uses the continuous clock, so it also elapses while the Mac sleeps; the model re-checks the wall clock
/// on wake and on clock changes anyway.
@MainActor final class SleepingWakeScheduler: TimerWakeScheduling {
    private var task: Task<Void, Never>?

    func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            let delay = max(date.timeIntervalSinceNow, 0)
            do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100)) } catch { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - The "timer done" sound

/// Plays the user's alert sound (DESIGN.md §14.3: a SYSTEM sound by name; Cranny ships none).
@MainActor protocol TimerSoundPlaying: AnyObject {
    func play(named name: String)
    func stop()
}

/// `NSSound(named:)` ("Glass" → /System/Library/Sounds/Glass.aiff). Plays once.
@MainActor final class SystemTimerSound: TimerSoundPlaying {
    private var current: NSSound?

    func play(named name: String) {
        current?.stop()
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            log.info("no system sound named \(name, privacy: .public)")
            current = nil
            return
        }
        current = sound
        sound.play()
    }

    func stop() {
        current?.stop()
        current = nil
    }
}

/// Previews, samples and tests: never makes a sound.
@MainActor final class SilentTimerSound: TimerSoundPlaying {
    private(set) var played: [String] = []
    private(set) var stops = 0
    func play(named name: String) { played.append(name) }
    func stop() { stops += 1 }
}

// MARK: - Everything the model touches outside itself

@MainActor struct TimerDependencies {
    var now: @MainActor () -> Date
    var scheduler: any TimerWakeScheduling
    var sound: any TimerSoundPlaying
    /// nil = nothing is persisted (previews, Settings samples, tests that do not test persistence).
    var file: TimerStateFile?
    /// Demo mode mutes everything (DESIGN.md §14.3).
    var isDemoMode: @MainActor () -> Bool
    /// `NotchControl.requestPeek` (the optional one-minute peek).
    var requestPeek: @MainActor (ActivityID) -> Void

    /// The app: wall clock, real sleeps, system sounds, `AppPaths/timer/state.json`, the shell's ports.
    static func live(services: CrannyServices) -> TimerDependencies {
        // The URL only: `register(in:)` does no file I/O. The first write creates the directory
        // (= `AppPaths.directory(for: .timer)`).
        let directory = services.paths.root.appending(path: ModuleID.timer.rawValue, directoryHint: .isDirectory)
        return TimerDependencies(now: { Date() }, scheduler: SleepingWakeScheduler(), sound: SystemTimerSound(),
                                 file: TimerStateFile(directory: directory),
                                 isDemoMode: { [environment = services.environment] in environment.isDemoMode },
                                 requestPeek: { [notch = services.notch] in notch.requestPeek($0) })
    }

    /// Settings "Simulate" samples, the onboarding stage and `#Preview`s: real time, nothing persisted, no sound.
    static func sample() -> TimerDependencies {
        TimerDependencies(now: { Date() }, scheduler: SleepingWakeScheduler(), sound: SilentTimerSound(), file: nil,
                          isDemoMode: { true }, requestPeek: { _ in })
    }
}
