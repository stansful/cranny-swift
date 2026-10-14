// A model runs only while one of its activities is enabled in Settings ▸ Live Activities (energy: the arbiter
// drops a disabled activity anyway).
import CrannyCore
import Foundation
import Testing
@testable import CrannySystemActivities

@MainActor @Suite struct ModelGateTests {
    let services = CrannyServices.preview()

    /// What the gate did to its model.
    @MainActor final class Calls { var log: [String] = [] }

    private func gate(_ calls: Calls) -> ModelGate {
        let settings = services.settings
        return ModelGate(isEnabled: { ModelGate.isEnabled(.bluetoothDevice, byDefault: true, in: settings) },
                         start: { calls.log.append("start") }, stop: { calls.log.append("stop") })
    }
    private func setBluetooth(enabled: Bool) {
        services.settings[CoreSettings.activityPreferences] = [.bluetoothDevice: ActivityPreference(isEnabled: enabled, peeksOnChange: false)]
    }
    private func settle(_ condition: () -> Bool) async -> Bool {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < 10 { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func anEnabledActivityStartsItsModelAtLaunch() {
        let calls = Calls()
        let gate = gate(calls)
        gate.open()
        #expect(calls.log == ["start"])
        #expect(gate.isRunning)
        gate.close()
        #expect(calls.log == ["start", "stop"])
        #expect(!gate.isRunning)
    }

    @Test func aDisabledActivityStartsNothing() {
        setBluetooth(enabled: false)
        let calls = Calls()
        let gate = gate(calls)
        gate.open()
        #expect(calls.log.isEmpty)
        gate.close()
        #expect(calls.log.isEmpty)                                    // never started: nothing to stop
    }

    @Test func theToggleStopsAndRestartsTheModel() async {
        let calls = Calls()
        let gate = gate(calls)
        gate.open()
        defer { gate.close() }
        setBluetooth(enabled: false)
        #expect(await settle { calls.log == ["start", "stop"] })
        setBluetooth(enabled: true)
        #expect(await settle { calls.log == ["start", "stop", "start"] })
    }

    @Test func otherPreferencesChangeNothing() async throws {
        let calls = Calls()
        let gate = gate(calls)
        gate.open()
        defer { gate.close() }
        services.settings[CoreSettings.activityPreferences] = [.charging: ActivityPreference(isEnabled: false, peeksOnChange: false)]
        try await Task.sleep(for: .milliseconds(50))
        #expect(calls.log == ["start"])
    }

    @Test func closingStopsFollowingTheToggle() async throws {
        let calls = Calls()
        let gate = gate(calls)
        gate.open()
        gate.close()
        setBluetooth(enabled: false)
        setBluetooth(enabled: true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(calls.log == ["start", "stop"])
    }
}
