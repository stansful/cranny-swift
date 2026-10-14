// Opt-in (ARCHITECTURE.md §9.6): how the real helper ends, outside BridgeConnection. A stand-in host (`/bin/sh`,
// which then becomes `/bin/sleep`) runs the helper under /usr/bin/perl on a stdin pipe whose write end this test
// keeps, like a descriptor leaked to another process. Killing the stand-in must end the helper at once even though
// stdin never reaches EOF: the helper watches its host with a process-exit source, never with a timer (§9.2: no
// polling while nothing plays; the old 5-s re-parenting check took 4–6 s here). The second test covers the usual
// path, stdin EOF. Only `ping` is sent; the helper reads (never changes) the Now Playing state while it runs.
//   CRANNY_INTEGRATION=1 CRANNY_MEDIA_BRIDGE=<path to libCrannyMediaBridge.dylib> swift test --filter BridgeLifetime
import Darwin
import Foundation
import os
import Testing
@testable import CrannyMedia

@Suite("Bridge lifetime integration", .enabled(if: ProcessInfo.processInfo.environment["CRANNY_INTEGRATION"] == "1"
                                               && ProcessInfo.processInfo.environment["CRANNY_MEDIA_BRIDGE"] != nil))
struct BridgeLifetimeIntegrationTests {
    @Test func exitsAsSoonAsItsHostDiesEvenWithStdinOpen() async throws {
        let run = try await StandInHost.launch()
        defer { run.tearDown() }
        #expect(run.helperParent == run.hostPID)          // the stand-in really is the helper's parent
        #expect(await run.pings())                        // the armed host watch leaves a live host's helper alone
        kill(run.hostPID, SIGKILL)
        let exit = try #require(await run.waitForHelperExit(timeout: .seconds(8)),
                                "the helper outlived its host while its stdin stayed open")
        #expect(exit < .seconds(2), "the helper noticed its host's exit only after \(exit)")
    }

    @Test func exitsOnStdinEOF() async throws {
        let run = try await StandInHost.launch()
        defer { run.tearDown() }
        run.closeStdin()
        let exit = try #require(await run.waitForHelperExit(timeout: .seconds(8)), "the helper ignored stdin EOF")
        #expect(exit < .seconds(2), "the helper exited \(exit) after stdin EOF")
        #expect(run.hostIsRunning)                        // EOF alone ended it, not its host's exit
    }
}

/// One helper run under a stand-in host the test can kill.
private final class StandInHost {
    let hostPID: pid_t
    let helperPID: pid_t
    private let host: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private let output: HelperOutput

    /// Starts the stand-in host and waits for the helper's `hello`.
    static func launch() async throws -> StandInHost {
        let dylib = try #require(ProcessInfo.processInfo.environment["CRANNY_MEDIA_BRIDGE"])
        let host = Process(), stdin = Pipe(), stdout = Pipe(), output = HelperOutput()
        host.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The helper gets the pipe through fd 3: a background job's stdin is otherwise /dev/null. Then the shell
        // becomes `sleep`, which stays the helper's parent until the test kills it.
        host.arguments = ["-c", #"exec 3<&0; /usr/bin/perl "$@" <&3 3<&- & exec /bin/sleep 120"#, "sh"]
            + BridgeConnection.Host.perl.arguments(dylib: dylib)
        host.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        host.standardInput = stdin
        host.standardOutput = stdout
        host.standardError = FileHandle.nullDevice
        // Drained all along: a helper blocked on a full stdout pipe could not run its exit handlers.
        stdout.fileHandleForReading.readabilityHandler = { handle in output.append(handle.availableData) }
        try host.run()
        guard let helperPID = await output.waitForHello(timeout: .seconds(10)) else {
            host.terminate()
            stdout.fileHandleForReading.readabilityHandler = nil
            throw StandInHostError.noHello
        }
        return StandInHost(host: host, stdin: stdin, stdout: stdout, output: output, helperPID: helperPID)
    }

    private init(host: Process, stdin: Pipe, stdout: Pipe, output: HelperOutput, helperPID: pid_t) {
        self.host = host
        self.stdin = stdin
        self.stdout = stdout
        self.output = output
        self.hostPID = host.processIdentifier
        self.helperPID = helperPID
    }

    var hostIsRunning: Bool { host.isRunning }

    /// The helper's parent PID right now (nil once it is gone).
    var helperParent: pid_t? { helperInfo?.kp_eproc.e_ppid }

    /// Running, not just present: after stdin EOF the helper stays a zombie of `sleep`, which never reaps it.
    private var helperIsAlive: Bool {
        guard let info = helperInfo else { return false }
        return Int32(info.kp_proc.p_stat) != SZOMB
    }

    private var helperInfo: kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, helperPID]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    /// Sends `ping` and waits for the `pong`.
    func pings() async -> Bool {
        let before = output.pongs
        try? stdin.fileHandleForWriting.write(contentsOf: Data("ping\n".utf8))
        return await poll(timeout: .seconds(2)) { self.output.pongs > before }
    }

    func closeStdin() { try? stdin.fileHandleForWriting.close() }

    /// Time until the helper was gone, or nil if it was still running after `timeout`.
    func waitForHelperExit(timeout: Duration) async -> Duration? {
        let start = ContinuousClock.now
        return await poll(timeout: timeout) { !self.helperIsAlive } ? ContinuousClock.now - start : nil
    }

    func tearDown() {
        if helperIsAlive { kill(helperPID, SIGKILL) }
        if host.isRunning { kill(hostPID, SIGKILL) }
        closeStdin()
        stdout.fileHandleForReading.readabilityHandler = nil
    }

    private func poll(timeout: Duration, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

private enum StandInHostError: Error { case noHello }

/// The helper's stdout, split into messages on the pipe's queue.
private nonisolated final class HelperOutput: Sendable {
    private struct State {
        var lines = LineBuffer(maxLineBytes: BridgeConnection.maxLineBytes, maxDroppedBytes: BridgeConnection.maxDroppedBytes)
        var helloPID: pid_t?
        var pongs = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        state.withLock { state in
            for case .line(let line) in state.lines.append(chunk) {
                switch BridgeMessage.parse(line) {
                case .hello(let pid)?: state.helloPID = pid
                case .pong?: state.pongs += 1
                default: break
                }
            }
        }
    }

    var pongs: Int { state.withLock { $0.pongs } }

    func waitForHello(timeout: Duration) async -> pid_t? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let pid = state.withLock({ $0.helloPID }) { return pid }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}
