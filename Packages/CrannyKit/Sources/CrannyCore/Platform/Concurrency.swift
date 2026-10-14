// CrannyCore/Platform/Concurrency.swift
// Small, verified building blocks so modules never hand-roll threading.
import Foundation
import Observation
import os

// MARK: - Observation outside SwiftUI (macOS 14-safe; `Observations` is macOS 26+)

/// Calls `onChange` with the new value whenever something `value()` reads changes.
/// Keep the returned token alive; `cancel()` (or releasing it) stops observing.
@MainActor public final class ObservationToken {
    fileprivate var observer: AnyObject?
    public func cancel() { observer = nil }
}

@MainActor @discardableResult
public func observe<T: Equatable>(_ value: @escaping @MainActor () -> T,
                                  onChange: @escaping @MainActor (T) -> Void) -> ObservationToken {
    let token = ObservationToken()
    let observer = Observer(value: value, onChange: onChange)
    token.observer = observer
    observer.arm()
    return token
}

@MainActor private final class Observer<T: Equatable> {
    let value: @MainActor () -> T
    let onChange: @MainActor (T) -> Void
    var last: T
    init(value: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
        self.value = value; self.onChange = onChange; self.last = value()
    }
    func arm() {
        withObservationTracking { _ = value() } onChange: { [weak self] in
            Task { @MainActor in self?.fire() }
        }
    }
    private func fire() {
        let now = value()
        if now != last { last = now; onChange(now) }
        arm()
    }
}

// MARK: - Debounce

/// Trailing debounce on the main actor (note autosave, settings-driven rebuilds).
@MainActor public final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?
    public init(delay: Duration) { self.delay = delay }
    public func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    public func cancel() { task?.cancel(); task = nil }
}

// MARK: - Subprocesses

public nonisolated struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public var succeeded: Bool { status == 0 }
}

public nonisolated enum ProcessRunError: Error, Sendable { case launchFailed(String) }

/// Runs a command-line tool off the main actor (`/usr/bin/shortcuts`, `/usr/bin/ditto`).
/// Both pipes are drained while the process runs (no pipe-buffer deadlock). Cancelling the calling task
/// terminates the process. Environment is minimal and explicit (never inherits PERL5LIB, DYLD_*).
public nonisolated enum ProcessRunner {
    @concurrent
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"],
                           currentDirectory: URL? = nil) async throws -> ProcessOutput {
        try await launch(executable, arguments, environment: environment, currentDirectory: currentDirectory,
                         interruptGrace: nil)
    }

    /// Like `run(_:_:environment:currentDirectory:)`, but cancelling the task first sends SIGINT — the tool's own
    /// Ctrl-C path, e.g. `shortcuts run` stops the shortcut it started — and SIGTERM only if the tool is still
    /// running `interruptGrace` later.
    @concurrent
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"],
                           currentDirectory: URL? = nil, interruptGrace: Duration) async throws -> ProcessOutput {
        try await launch(executable, arguments, environment: environment, currentDirectory: currentDirectory,
                         interruptGrace: interruptGrace)
    }

    @concurrent
    private static func launch(_ executable: String, _ arguments: [String], environment: [String: String],
                               currentDirectory: URL?, interruptGrace: Duration?) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessOutput, any Error>) in
                let collector = OutputCollector()
                out.fileHandleForReading.readabilityHandler = { collector.append($0.availableData, error: false) }
                err.fileHandleForReading.readabilityHandler = { collector.append($0.availableData, error: true) }
                process.terminationHandler = { p in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    collector.append(out.fileHandleForReading.readDataToEndOfFile(), error: false)
                    collector.append(err.fileHandleForReading.readDataToEndOfFile(), error: true)
                    let (o, e) = collector.result
                    cont.resume(returning: ProcessOutput(status: p.terminationStatus, stdout: o, stderr: e))
                }
                do {
                    // Cancelled before the launch: never start it; report it like a process killed by SIGTERM.
                    guard try box.run() else {
                        process.terminationHandler = nil
                        out.fileHandleForReading.readabilityHandler = nil
                        err.fileHandleForReading.readabilityHandler = nil
                        cont.resume(returning: ProcessOutput(status: SIGTERM, stdout: Data(), stderr: Data()))
                        return
                    }
                } catch {
                    process.terminationHandler = nil
                    cont.resume(throwing: ProcessRunError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if let interruptGrace { box.interrupt(thenTerminateAfter: interruptGrace) } else { box.terminate() }
        }
    }
}

/// Launch and cancellation of one process, serialized by `cancellation` so a cancellation that arrives before the
/// launch is not lost (it used to find no running process, and the tool then ran to the end).
private nonisolated final class ProcessBox: @unchecked Sendable {   // `process` is only touched under the lock
    private let process: Process
    /// Whether the task was cancelled; the lock also serializes `Process.run()` against the signals.
    private let cancellation = OSAllocatedUnfairLock(initialState: false)
    init(_ p: Process) { process = p }

    /// Launches the process; false (not launched) when the task was cancelled first.
    func run() throws -> Bool {
        try cancellation.withLockUnchecked { cancelled in
            guard !cancelled else { return false }
            try process.run()
            return true
        }
    }

    func terminate() {
        cancellation.withLockUnchecked { cancelled in
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    /// SIGINT now, SIGTERM after `grace` if the process has not exited by then.
    func interrupt(thenTerminateAfter grace: Duration) {
        let interrupted = cancellation.withLockUnchecked { cancelled -> Bool in
            cancelled = true
            guard process.isRunning else { return false }
            process.interrupt()
            return true
        }
        guard interrupted else { return }
        let (seconds, attoseconds) = grace.components
        let delay = Double(seconds) + Double(attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in terminate() }
    }
}

private nonisolated final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    func append(_ d: Data, error: Bool) {
        guard !d.isEmpty else { return }
        lock.withLock { if error { err.append(d) } else { out.append(d) } }
    }
    var result: (Data, Data) { lock.withLock { (out, err) } }
}
