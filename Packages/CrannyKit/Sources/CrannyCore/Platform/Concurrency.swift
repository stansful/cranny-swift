// CrannyCore/Platform/Concurrency.swift
// Small, verified building blocks so modules never hand-roll threading.
import Foundation
import Observation
import os

// MARK: - Observation outside SwiftUI (macOS 14-safe; `Observations` is macOS 26+)

/// Keeps an `observe(_:onChange:)` registration alive. Keep the token; `cancel()` (or releasing it) stops observing.
@MainActor public final class ObservationToken {
    fileprivate var observer: AnyObject?
    /// Stops observing; `onChange` is not called again.
    public func cancel() { observer = nil }
}

/// Calls `onChange` with the new value whenever something `value()` reads changes (Observation outside SwiftUI).
/// `value()` runs once at registration and once per change: each run both reads the value and registers what it
/// reads, so keep it cheap but never split it. `onChange` runs on the main actor, after the change, only when the
/// value differs from the last one delivered. Keep the returned token alive.
@MainActor @discardableResult
public func observe<T: Equatable>(_ value: @escaping @MainActor () -> T,
                                  onChange: @escaping @MainActor (T) -> Void) -> ObservationToken {
    let token = ObservationToken()
    let observer = Observer(value: value, onChange: onChange)
    token.observer = observer
    observer.start()
    return token
}

@MainActor private final class Observer<T: Equatable> {
    let value: @MainActor () -> T
    let onChange: @MainActor (T) -> Void
    /// The value delivered last (set by `start()` before anything can fire).
    private var last: T?
    init(value: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
        self.value = value; self.onChange = onChange
    }
    func start() { last = arm() }
    /// Evaluates `value` ONCE: the same pass returns the value and registers what it read for the next change.
    private func arm() -> T {
        withObservationTracking { value() } onChange: { [weak self] in
            Task { @MainActor in self?.fire() }
        }
    }
    private func fire() {
        let now = arm()
        if now != last { last = now; onChange(now) }
    }
}

// MARK: - Durations

public extension Duration {
    /// Seconds as a `TimeInterval`, for `Date` and `DispatchTime` arithmetic and for logging.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

// MARK: - Debounce

/// Trailing debounce on the main actor (note autosave, settings-driven rebuilds).
///
/// Energy: the action's task runs at `priority`; nil inherits the caller's (on the main actor: user-initiated). Pass
/// `.utility` for work nobody waits on, such as background saves and notification-driven reloads: the `@concurrent`
/// work the action awaits then runs at utility QoS (efficiency cores, throttled I/O).
@MainActor public final class Debouncer {
    private let delay: Duration
    private let priority: TaskPriority?
    private var task: Task<Void, Never>?
    /// A debouncer that waits `delay` after the last `schedule(_:)`; its actions run at `priority` (nil: inherited).
    public init(delay: Duration, priority: TaskPriority? = nil) {
        self.delay = delay
        self.priority = priority
    }
    /// Runs `action` after the delay unless another `schedule` or `cancel` comes first.
    public func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task(priority: priority) { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    /// Drops the pending action.
    public func cancel() { task?.cancel(); task = nil }
}

// MARK: - Subprocesses

/// What a finished command-line tool left: its exit status and both pipes.
public nonisolated struct ProcessOutput: Sendable {
    /// The exit status (or the signal that ended it).
    public let status: Int32
    /// Everything written to standard output.
    public let stdout: Data
    /// Everything written to standard error.
    public let stderr: Data
    /// Exit status 0.
    public var succeeded: Bool { status == 0 }
}

/// The tool could not be started (the description says why).
public nonisolated enum ProcessRunError: Error, Sendable { case launchFailed(String) }

/// Runs a command-line tool off the main actor (`/usr/bin/shortcuts`, `/usr/bin/ditto`).
/// Both pipes are drained while the process runs (no pipe-buffer deadlock). Cancelling the calling task
/// terminates the process. Environment is minimal and explicit (never inherits PERL5LIB, DYLD_*).
/// Energy: `qualityOfService` sets the tool's own QoS (`Process.qualityOfService`); nil leaves `Process`'s default.
/// Pass `.utility` for batch work with a progress indicator that nobody waits on (the Tray's Zip and Unzip).
public nonisolated enum ProcessRunner {
    /// Runs `executable` with `arguments` to completion; cancelling the task terminates it (SIGTERM).
    @concurrent
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"],
                           currentDirectory: URL? = nil,
                           qualityOfService: QualityOfService? = nil) async throws -> ProcessOutput {
        try await launch(executable, arguments, environment: environment, currentDirectory: currentDirectory,
                         interruptGrace: nil, qualityOfService: qualityOfService)
    }

    /// Like `run(_:_:environment:currentDirectory:qualityOfService:)`, but cancelling the task first sends SIGINT —
    /// the tool's own Ctrl-C path, e.g. `shortcuts run` stops the shortcut it started — and SIGTERM only if the tool
    /// is still running `interruptGrace` later.
    @concurrent
    public static func run(_ executable: String, _ arguments: [String],
                           environment: [String: String] = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"],
                           currentDirectory: URL? = nil, interruptGrace: Duration,
                           qualityOfService: QualityOfService? = nil) async throws -> ProcessOutput {
        try await launch(executable, arguments, environment: environment, currentDirectory: currentDirectory,
                         interruptGrace: interruptGrace, qualityOfService: qualityOfService)
    }

    @concurrent
    private static func launch(_ executable: String, _ arguments: [String], environment: [String: String],
                               currentDirectory: URL?, interruptGrace: Duration?,
                               qualityOfService: QualityOfService?) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let qualityOfService { process.qualityOfService = qualityOfService }
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
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace.timeInterval) { [self] in terminate() }
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
