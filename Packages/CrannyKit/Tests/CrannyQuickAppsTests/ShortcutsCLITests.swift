// The Shortcuts CLI wrapper: arguments, error mapping and cancellation. The process tests run temporary shell
// scripts through the real `ProcessRunner` in place of `/usr/bin/shortcuts`, so no shortcut ever runs.
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func listPassesShowIdentifiersAndParses() async throws {
    let fake = FakeCLI(listing: shortcutListFixture)
    let list = try await fake.cli.list()
    #expect(fake.calls == [["list", "--show-identifiers"]])
    #expect(list.count == 9)
}

@Test func runPassesTheIdentifier() async throws {
    let fake = FakeCLI()
    try await fake.cli.run("0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01")
    #expect(fake.calls == [["run", "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01"]])
}

@Test func nonZeroExitMapsToTheOperationsError() async {
    let failing = FakeCLI { _ in CLIOutput(status: 1, stderr: Data("Error: nope".utf8)) }
    await #expect(throws: QuickAppsError.shortcutFailed) { try await failing.cli.run("X") }
    await #expect(throws: QuickAppsError.listFailed) { _ = try await failing.cli.list() }
}

@Test func launchFailureMeansShortcutsIsUnavailable() async {
    let cli = ShortcutsCLI(executable: "/nonexistent/cranny-tests/shortcuts")
    await #expect(throws: QuickAppsError.shortcutsUnavailable) { _ = try await cli.list() }
}

@Test func alreadyCancelledTaskNeverStartsTheTool() async {
    let fake = FakeCLI()
    let task = Task { try await fake.cli.run("X") }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(fake.calls.isEmpty)
}

@Test func realProcessListAndRunArguments() async throws {
    let (script, directory) = try makeScript("""
        echo "$@" >> "$(dirname "$0")/arguments"
        if [ "$1" = list ]; then printf '%s\\n' 'Résumé (draft) (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)'; fi
        """)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cli = ShortcutsCLI(executable: script.path)
    let list = try await cli.list()
    try await cli.run("0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01")
    #expect(list == [ShortcutInfo(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Résumé (draft)")])
    let arguments = try String(contentsOf: directory.appending(path: "arguments"), encoding: .utf8)
    #expect(arguments == "list --show-identifiers\nrun 0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01\n")
}

@Test func realProcessFailureIsAFailure() async throws {
    let (script, directory) = try makeScript("echo 'Error: The shortcut failed.' >&2; exit 1")
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: QuickAppsError.shortcutFailed) { try await ShortcutsCLI(executable: script.path).run("X") }
}

@Test func cancellingARunTerminatesTheProcess() async throws {
    let (script, directory) = try makeScript("exec /bin/sleep 30")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cli = ShortcutsCLI(executable: script.path)
    let started = ContinuousClock.now
    let task = Task { try await cli.run("X") }
    try await Task.sleep(for: .milliseconds(300))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(ContinuousClock.now - started < .seconds(5))      // not the script's 30 s
}

@Test func stoppingARunInterruptsTheCLIFirst() async throws {
    // `shortcuts run` stops the shortcut on SIGINT (its Ctrl-C handler); SIGTERM would kill only the CLI.
    let (script, directory) = try makeScript("""
        dir="$(dirname "$0")"
        trap 'touch "$dir/interrupted"; echo "Running was cancelled" >&2; exit 1' INT
        trap 'touch "$dir/terminated"; exit 1' TERM
        touch "$dir/ready"
        while :; do /bin/sleep 0.05; done
        """)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cli = ShortcutsCLI(executable: script.path)
    let task = Task { try await cli.run("X") }
    #expect(await waitUntil { FileManager.default.fileExists(atPath: directory.appending(path: "ready").path) })
    let cancelled = ContinuousClock.now
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }   // a stop, not a failure
    #expect(ContinuousClock.now - cancelled < ShortcutsCLI.interruptGrace)
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "interrupted").path))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "terminated").path))
}

@Test func aListThatDoesNotAnswerFailsAfterItsTimeout() async {
    let gate = Gate()
    defer { gate.open() }
    let hung = FakeCLI { _ in await gate.wait(); return CLIOutput() }
    await #expect(throws: QuickAppsError.listFailed) { _ = try await hung.cli(listTimeout: .milliseconds(100)).list() }
    #expect(!gate.isOpen)                                         // answered while the CLI was still stuck
    #expect(gate.sawCancellation)                                 // the live runner interrupts the CLI here
}

@Test func aRunHasNoTimeLimit() async throws {
    let slow = FakeCLI(runDuration: .milliseconds(300))
    try await slow.cli(listTimeout: .milliseconds(50)).run("X")   // a shortcut may run for minutes
    #expect(slow.calls == [["run", "X"]])
}

@Test func realProcessListThatHangsIsStoppedAtItsTimeout() async throws {
    let (script, directory) = try makeScript("""
        echo $$ > "$(dirname "$0")/pid"
        exec /bin/sleep 30
        """)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cli = ShortcutsCLI(executable: script.path, listTimeout: .milliseconds(500))
    let started = ContinuousClock.now
    await #expect(throws: QuickAppsError.listFailed) { _ = try await cli.list() }
    #expect(ContinuousClock.now - started < .seconds(10))         // not the script's 30 s
    let pid = try #require(Int32(String(contentsOf: directory.appending(path: "pid"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(await waitUntil { kill(pid, 0) != 0 })                 // the CLI was stopped, not left running
}
