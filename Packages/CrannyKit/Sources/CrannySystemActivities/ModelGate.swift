// CrannySystemActivities/ModelGate.swift — runs a model only while one of its activities is enabled in
// Settings ▸ Live Activities (§9.2: no work nobody sees). The shell's arbiter drops a disabled activity anyway,
// so a model left running would only keep IOKit, Core Audio and powerd busy for activities nobody can see.
// Turning a toggle back on starts the model as at launch: its first reports are a baseline again.
import CrannyCore
import Foundation

@MainActor final class ModelGate {
    private let isEnabled: @MainActor () -> Bool
    private let start: @MainActor () -> Void
    private let stop: @MainActor () -> Void
    private var token: ObservationToken?
    /// The model runs (started by this gate and not stopped since).
    private(set) var isRunning = false

    /// - Parameter isEnabled: read through Observation (settings), so a toggle starts or stops the model.
    init(isEnabled: @escaping @MainActor () -> Bool, start: @escaping @MainActor () -> Void,
         stop: @escaping @MainActor () -> Void) {
        self.isEnabled = isEnabled; self.start = start; self.stop = stop
    }

    /// From `onLaunch`: starts the model if enabled, then follows the toggles.
    func open() {
        guard token == nil else { return }
        token = observe(isEnabled) { [weak self] _ in self?.sync() }
        sync()
    }

    /// From `onTerminate`: stops following and stops the model.
    func close() {
        token = nil
        guard isRunning else { return }
        isRunning = false
        stop()
    }

    private func sync() {
        let wanted = isEnabled()
        guard wanted != isRunning else { return }
        isRunning = wanted
        if wanted { start() } else { stop() }
    }

    /// The Settings ▸ Live Activities toggle of the activity `id`, as the shell's arbiter reads it.
    static func isEnabled(_ id: ActivityID, byDefault: Bool, in settings: SettingsStore) -> Bool {
        settings[CoreSettings.activityPreferences][id]?.isEnabled ?? byDefault
    }
}
