// CrannyTimer/Model/TimerModel+Sample.swift — self-contained sample timers for the Settings "Simulate" chips, the
// onboarding stage and `#Preview`s (ARCHITECTURE.md §3.6: a sample never touches the module's real model).
import CrannyCore
import Foundation

extension TimerModel {
    enum Sample {
        case idle
        case setup(seconds: Int)
        case running(left: TimeInterval, total: TimeInterval)
        case paused(left: TimeInterval, total: TimeInterval)
        case done(total: TimeInterval)

        /// The state (and set-up draft) this sample stands for at `now`.
        func state(at now: Date) -> (state: TimerState, draft: Int?) {
            switch self {
            case .idle: (TimerState(), nil)
            case .setup(let seconds): (TimerState(), seconds)
            case .running(let left, let total): (TimerState(phase: .running(endDate: now.addingTimeInterval(left)), total: total), nil)
            case .paused(let left, let total): (TimerState(phase: .paused(remaining: left), total: total), nil)
            case .done(let total): (TimerState(phase: .done(at: now), total: total), nil)
            }
        }
    }

    /// Real time, nothing persisted, no sound, no peeks. `settings` supplies the presets (in-memory by default).
    static func sample(_ sample: Sample, settings: SettingsStore? = nil) -> TimerModel {
        let store = settings ?? SettingsStore(defaults: UserDefaults(suiteName: "cranny.timer.sample.\(UUID().uuidString)") ?? .standard)
        let model = TimerModel(settings: store, dependencies: .sample())
        let (state, draft) = sample.state(at: model.now)
        model.showSample(state, draft: draft)
        return model
    }
}
