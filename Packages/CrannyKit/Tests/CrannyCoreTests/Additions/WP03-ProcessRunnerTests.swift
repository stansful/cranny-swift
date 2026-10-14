// Core change request from WP3 (Quick Apps): `ProcessRunner` cancellation. A cancellation that arrives before the
// launch is kept (the tool never starts), and `run(…, interruptGrace:)` stops a tool through SIGINT first, its own
// Ctrl-C path, escalating to SIGTERM. Temporary shell scripts stand in for the tools.
import Foundation
import Testing
@testable import CrannyCore

/// A temporary executable shell script; the caller removes `directory`.
private func makeScript(_ body: String) throws -> (url: URL, directory: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "cranny-core-process-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "tool")
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, directory)
}

/// Polls until `path` exists (or fails after `timeout`).
private func waitForFile(_ path: String, timeout: Duration = .seconds(5)) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !FileManager.default.fileExists(atPath: path) {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Test func processRunnerCancelledBeforeLaunchNeverStarts() async throws {
    let (script, directory) = try makeScript("touch \"$(dirname \"$0\")/started\"; exec /bin/sleep 30")
    defer { try? FileManager.default.removeItem(at: directory) }
    let started = ContinuousClock.now
    let task = Task { try await ProcessRunner.run(script.path, []) }
    task.cancel()                                     // before the task got to run at all
    let output = try await task.value
    #expect(output.status == SIGTERM)                 // reported like a terminated process
    #expect(ContinuousClock.now - started < .seconds(5))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "started").path))
}

@Test func processRunnerInterruptsFirstWhenAskedTo() async throws {
    // The tool handles SIGINT itself (as `shortcuts run` does) and exits cleanly; SIGTERM would skip the handler.
    let (script, directory) = try makeScript("""
        dir="$(dirname "$0")"
        trap 'touch "$dir/interrupted"; exit 0' INT
        trap 'touch "$dir/terminated"; exit 0' TERM
        touch "$dir/ready"
        while :; do /bin/sleep 0.05; done
        """)
    defer { try? FileManager.default.removeItem(at: directory) }
    let task = Task { try await ProcessRunner.run(script.path, [], interruptGrace: .seconds(10)) }
    #expect(await waitForFile(directory.appending(path: "ready").path))
    let cancelled = ContinuousClock.now
    task.cancel()
    _ = try await task.value
    #expect(ContinuousClock.now - cancelled < .seconds(5))    // the tool's handler ran, no grace wait
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "interrupted").path))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "terminated").path))
}

@Test func processRunnerTerminatesWhenAnInterruptIsIgnored() async throws {
    let (script, directory) = try makeScript("""
        trap '' INT
        touch "$(dirname "$0")/ready"
        exec /bin/sleep 30
        """)
    defer { try? FileManager.default.removeItem(at: directory) }
    let task = Task { try await ProcessRunner.run(script.path, [], interruptGrace: .milliseconds(300)) }
    #expect(await waitForFile(directory.appending(path: "ready").path))
    let cancelled = ContinuousClock.now
    task.cancel()
    let output = try await task.value
    #expect(output.status == SIGTERM)                 // SIGTERM after the grace, not the 30-s sleep
    #expect(ContinuousClock.now - cancelled < .seconds(5))
}

@Test func processRunnerInterruptOptionStillReportsOutput() async throws {
    let output = try await ProcessRunner.run("/bin/sh", ["-c", "echo done; exit 4"], interruptGrace: .seconds(1))
    #expect(output.status == 4)
    #expect(String(decoding: output.stdout, as: UTF8.self) == "done\n")
}
