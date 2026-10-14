// Launch, quit and display changes (ARCHITECTURE.md §3.4, §4.9): terminate hooks only after launch hooks, and one
// display rule for the panels and the menu's Show On ▸ checkmarks.
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

// MARK: - Show On ▸ (C-SHELL-5)

private let notchedLaptop = ConnectedDisplay(key: "built-in", name: "Built-in Retina Display", isBuiltIn: true, hasNotch: true)
private let external = ConnectedDisplay(key: "external", name: "DELL U2723QE", isBuiltIn: false, hasNotch: false)

/// "Only on my external monitor": the notched built-in display is set to Off in General ▸ Displays. The menu checks
/// exactly the displays with a panel, the last one cannot be unchecked, and checking the laptop again shows its notch.
@Test func showOnAgreesWithThePanelsForANotchedDisplaySetToOff() throws {
    let off: [DisplayKey: DisplayPreferences] = ["built-in": DisplayPreferences(style: .off)]
    let policy = ShowOnPolicy(selection: .all, perDisplay: off, noNotchStyle: .floatingIsland)
    let displays = [notchedLaptop, external]
    let descriptors = displays.enumerated().map { index, display in
        DisplayDescriptor(key: display.key, displayID: CGDirectDisplayID(index + 1), isBuiltIn: display.isBuiltIn,
                          hasNotch: display.hasNotch, isPrimary: index == 0)
    }
    let panels = DisplayCatalog.placements(for: descriptors, selection: .all, perDisplay: off, noNotchStyle: .floatingIsland)
    #expect(panels.map(\.key) == ["external"])
    #expect(policy.shownKeys(on: displays) == ["external"])
    #expect(!policy.canToggle("external", on: displays))                        // Cranny never vanishes everywhere
    #expect(policy.toggling("external", on: displays) == policy)
    let laptopBack = policy.toggling("built-in", on: displays)
    #expect(laptopBack.perDisplay["built-in"]?.style == nil)                    // Automatic: the notch
    #expect(laptopBack.shownKeys(on: displays) == ["built-in", "external"] && laptopBack.selection == .all)
    // Every selection: the checkmarks are the panels.
    for selection in [DisplaySelection.builtIn, .all, .pointer, .custom(["built-in"]), .custom(["external"]), .custom([])] {
        let shown = ShowOnPolicy(selection: selection, perDisplay: off, noNotchStyle: .floatingIsland).shownKeys(on: displays)
        let placed = DisplayCatalog.placements(for: descriptors, selection: selection, perDisplay: off, noNotchStyle: .floatingIsland)
        #expect(shown == Set(placed.map(\.key)), "\(selection)")
    }
}

