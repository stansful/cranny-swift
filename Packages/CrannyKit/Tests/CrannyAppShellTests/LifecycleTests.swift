// Launch and quit (ARCHITECTURE.md §3.4): terminate hooks only after launch hooks.
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Testing
@testable import CrannyAppShell

// MARK: - Launch and quit (C-SHELL-6)

/// Records what happens, in order (the gate's callbacks run on the main actor), and holds a launch hook until released.
@MainActor private final class Journal {
    var entries: [String] = []
    var release: CheckedContinuation<Void, Never>?
    func waitForRelease() async { await withCheckedContinuation { release = $0 } }
}

/// `--diagnostics` (and `make smoke`) quits before any module launched: no terminate hook may save the unrestored
/// timer or delete the Tray's work folder then.
@Test func noTerminateHooksWithoutALaunch() {
    let gate = LaunchGate()
    #expect(gate.phase == .notLaunched && !gate.runsTerminateHooks)
    #expect(!gate.defersQuit { Issue.record("nothing to wait for") })
}

/// A quit while the launch hooks run waits for them, then the terminate hooks may run.
@Test func aQuitDuringTheLaunchWaitsForIt() async throws {
    let gate = LaunchGate()
    let journal = Journal()
    gate.launch {
        await journal.waitForRelease()
        journal.entries.append("launched")
    }
    #expect(gate.phase == .launching && gate.runsTerminateHooks)
    #expect(gate.defersQuit { journal.entries.append("quit") })
    #expect(gate.defersQuit { journal.entries.append("second quit") })        // shares the first reply
    for _ in 0..<100 where journal.release == nil { try await Task.sleep(for: .milliseconds(10)) }
    #expect(journal.entries.isEmpty)
    journal.release?.resume()
    for _ in 0..<100 where !journal.entries.contains("quit") { try await Task.sleep(for: .milliseconds(10)) }
    #expect(journal.entries == ["launched", "quit"] && gate.phase == .launched)
    #expect(!gate.defersQuit { Issue.record("launched: quits at once") })
}

/// A launch hook that never finishes cannot block quitting.
@Test func aHungLaunchDelaysTheQuitOnlySoLong() async throws {
    let gate = LaunchGate()
    let journal = Journal()
    gate.launch { try? await Task.sleep(for: .seconds(60)) }
    #expect(gate.defersQuit(atMost: .milliseconds(50)) { journal.entries.append("quit") })
    for _ in 0..<200 where journal.entries.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(journal.entries == ["quit"] && gate.phase == .launching)
}

