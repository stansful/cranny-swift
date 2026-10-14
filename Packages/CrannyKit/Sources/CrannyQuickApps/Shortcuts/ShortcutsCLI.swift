// CrannyQuickApps/Shortcuts/ShortcutsCLI.swift — `/usr/bin/shortcuts list` and `run` (ARCHITECTURE.md §7.6, R3 §6).
//
// Threading: `ProcessRunner.run` is `@concurrent`, so the process is launched and drained off the main actor.
// Stopping: cancelling the calling task sends SIGINT, the CLI's own Ctrl-C path. On macOS 27.0.1 `shortcuts`
// handles SIGINT itself (a dispatch signal source; "Running was cancelled") and stops the run, while SIGTERM would
// kill only the CLI process; SIGTERM follows if it has not exited after `interruptGrace`.
// The CLI needs no permission of its own (R3 §6); a shortcut's actions may ask on behalf of Shortcuts. Shortcuts
// run by identifier so a rename in Shortcuts.app keeps working.
import CrannyCore
import Foundation
import os

nonisolated private let log = Log.logger(.quickApps)

/// Exit status and output of one CLI call (Core's `ProcessOutput` has no public initializer for fakes).
nonisolated struct CLIOutput: Sendable, Equatable {
    var status: Int32
    var stdout: Data
    var stderr: Data
    var succeeded: Bool { status == 0 }

    init(status: Int32 = 0, stdout: Data = Data(), stderr: Data = Data()) {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
}

nonisolated struct ShortcutsCLI: Sendable {
    /// Launches a tool and returns its exit status and output (tests inject fakes; the app uses `ProcessRunner`).
    typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) async throws -> CLIOutput

    static let defaultExecutable = "/usr/bin/shortcuts"

    let executable: String
    private let runner: Runner

    init(executable: String = Self.defaultExecutable,
         runner: @escaping Runner = Self.processRunner) {
        self.executable = executable
        self.runner = runner
    }

    /// How long a stopped CLI may take to stop its shortcut before it is terminated.
    static let interruptGrace: Duration = .seconds(2)

    /// The live runner: `ProcessRunner` off the main actor; cancellation interrupts, then terminates the process.
    static let processRunner: Runner = { executable, arguments in
        let output = try await ProcessRunner.run(executable, arguments, interruptGrace: interruptGrace)
        return CLIOutput(status: output.status, stdout: output.stdout, stderr: output.stderr)
    }

    /// Every shortcut in Shortcuts.app, in its order (≈ 20 ms on macOS 27).
    func list() async throws -> [ShortcutInfo] {
        let output = try await execute(["list", "--show-identifiers"], failure: .listFailed)
        return ShortcutListParser.parse(output.stdout)
    }

    /// Runs the shortcut with this identifier and returns when it finished. Throws `CancellationError` when the
    /// calling task was cancelled (the CLI is interrupted, which stops the shortcut), `QuickAppsError` when it failed.
    func run(_ id: String) async throws {
        _ = try await execute(["run", id], failure: .shortcutFailed)
    }

    private func execute(_ arguments: [String], failure: QuickAppsError) async throws -> CLIOutput {
        try Task.checkCancellation()
        let output: CLIOutput
        do {
            output = try await runner(executable, arguments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.error("shortcuts \(arguments.first ?? "", privacy: .public) could not start: \(error.localizedDescription, privacy: .public)")
            throw QuickAppsError.shortcutsUnavailable
        }
        // An interrupted or terminated CLI exits with an error status: report the cancellation, not a failure.
        try Task.checkCancellation()
        guard output.succeeded else {
            let message = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            log.error("shortcuts \(arguments.first ?? "", privacy: .public) exited \(output.status, privacy: .public): \(message, privacy: .private)")
            throw failure
        }
        return output
    }
}
