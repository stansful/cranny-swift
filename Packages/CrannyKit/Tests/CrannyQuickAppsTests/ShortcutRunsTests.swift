// Run states of shortcut tiles: running → finished/failed (badges reset by one sleep each), stop, quit.
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func successShowsACheckThenReturnsToIdle() async {
    let runs = ShortcutRuns(cli: FakeCLI().cli, successHold: .milliseconds(50))
    var outcome: ShortcutRunOutcome?
    #expect(runs.start("A") { outcome = $0 })
    #expect(runs.isRunning("A"))
    #expect(await waitUntil { outcome != nil })
    #expect(outcome == .succeeded)
    #expect(runs.state(of: "A") == .succeeded)
    #expect(await waitUntil { runs.state(of: "A") == .idle })
}

@Test func failureShowsABadgeUntilItsHoldEnds() async {
    let runs = ShortcutRuns(cli: FakeCLI(failing: ["A"]).cli, failureHold: .milliseconds(80))
    var outcome: ShortcutRunOutcome?
    runs.start("A") { outcome = $0 }
    #expect(await waitUntil { outcome != nil })
    #expect(outcome == .failed(.shortcutFailed))
    #expect(runs.state(of: "A") == .failed(.shortcutFailed))
    runs.replaceFailure(of: "A", with: .shortcutNotFound)
    #expect(runs.state(of: "A") == .failed(.shortcutNotFound))
    #expect(await waitUntil { runs.state(of: "A") == .idle })
}

@Test func stoppingARunLeavesNoBadge() async {
    let runs = ShortcutRuns(cli: FakeCLI(runDuration: .seconds(30)).cli)
    var outcome: ShortcutRunOutcome?
    runs.start("A") { outcome = $0 }
    #expect(runs.hasRunningShortcuts)
    runs.cancel("A")
    #expect(await waitUntil { outcome != nil })
    #expect(outcome == .cancelled)
    #expect(runs.state(of: "A") == .idle)
}

@Test func aRunningShortcutIsNotStartedTwice() async {
    let fake = FakeCLI(runDuration: .seconds(30))
    let runs = ShortcutRuns(cli: fake.cli)
    #expect(runs.start("A"))
    #expect(!runs.start("A"))
    #expect(runs.start("B"))
    #expect(await waitUntil { fake.calls.count == 2 })
    runs.cancelAll()
    #expect(await waitUntil { !runs.hasRunningShortcuts })
}

@Test func runningAgainClearsThePreviousResult() async {
    let runs = ShortcutRuns(cli: FakeCLI(failing: ["A"]).cli, failureHold: .seconds(60))
    var finished = 0
    runs.start("A") { _ in finished += 1 }
    #expect(await waitUntil { finished == 1 })
    runs.start("A") { _ in finished += 1 }
    #expect(runs.isRunning("A"))
    #expect(await waitUntil { finished == 2 })
    runs.cancelAll()
}

@Test func runningRingFillsButNeverCompletes() {
    #expect(RunningRing.progress(elapsed: 0) > 0.1)
    #expect(RunningRing.progress(elapsed: 4) > RunningRing.progress(elapsed: 1))
    #expect(RunningRing.progress(elapsed: 3600) < 0.91)
    #expect(RunningRing.progress(elapsed: -5) == RunningRing.progress(elapsed: 0))
}
