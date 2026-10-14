// CrannyMedia/Providers/BridgeConnection.swift — one running bridge helper: an Apple-signed interpreter
// (`/usr/bin/perl`, fallback `/usr/bin/ruby`) that loads libCrannyMediaBridge.dylib and speaks NDJSON on stdout
// and one text command per line on stdin (ARCHITECTURE.md §6.3, R2 §4).
//
// Threading: the process, the pipes, the line buffer, the ping waiters and the command waiters are confined to
// `queue` (a private serial queue). Pipe and termination callbacks hop onto it. Callers may use the public methods
// from any thread; `onMessage`/`onEnd` are called on `queue`. The interpreter is spawned on `queue` too (`start`
// returns at once: posix_spawn and Process's setup never run on the caller's thread, the main thread at launch).
import CrannyCore
import Foundation
import os

private nonisolated let log = Log.logger(.mediaBridge)

nonisolated final class BridgeConnection: @unchecked Sendable {   // every mutable field is confined to `queue`
    /// The Apple-signed interpreters that may host the bridge (mediaremoted admits `com.apple.perl/ruby`).
    enum Host: String, Sendable, CaseIterable {
        case perl = "/usr/bin/perl"
        case ruby = "/usr/bin/ruby"

        /// Loader programs are passed with `-e`, so no script file is bundled (R2 §4, verified).
        func arguments(dylib: String) -> [String] {
            switch self {
            case .perl:
                return ["-e", #"use strict; use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error() . "\n"; my $s = DynaLoader::dl_find_symbol($h, "cranny_bridge_main") or die "entry missing\n"; DynaLoader::dl_install_xsub("main::bridge", $s); bridge();"#, dylib]
            case .ruby:
                return ["-e", #"require "fiddle"; h = Fiddle.dlopen(ARGV[0]); Fiddle::Function.new(h["cranny_bridge_main"], [], Fiddle::TYPE_VOID).call"#, dylib]
            }
        }
        var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: rawValue) }
    }

    /// perl + dylib + MediaRemote normally say hello in ≈ 0.4 s (R2 test b2).
    static let handshakeTimeout: TimeInterval = 4
    /// A line longer than this is dropped and the helper keeps running (the bridge shrinks artwork above 1 MB,
    /// so only an artwork it could not shrink gets here).
    static let maxLineBytes = 8 << 20
    /// A corrupt or runaway stream: this many bytes without any newline terminates the helper.
    static let maxDroppedBytes = 64 << 20
    /// How long a command waits for the helper's `ack` (it normally takes ≈ 12 ms, R2).
    static let commandTimeout: Duration = .seconds(1)

    private let queue = DispatchQueue(label: "app.cranny.media.bridge", qos: .utility)
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private var lines = LineBuffer(maxLineBytes: BridgeConnection.maxLineBytes, maxDroppedBytes: BridgeConnection.maxDroppedBytes)
    private var acks = CommandAcks<(Bool?) -> Void>()
    private var closedByUs = false
    private var gotHello = false
    private var pingWaiters: [(id: UUID, sent: ContinuousClock.Instant, resume: (Duration?) -> Void)] = []
    private let onMessage: @Sendable (BridgeMessage) -> Void
    private let onEnd: @Sendable (ProviderFailure) -> Void

    init(host: Host, dylib: URL,
         onMessage: @escaping @Sendable (BridgeMessage) -> Void,
         onEnd: @escaping @Sendable (ProviderFailure) -> Void) {
        self.onMessage = onMessage
        self.onEnd = onEnd
        process.executableURL = URL(fileURLWithPath: host.rawValue)
        process.arguments = host.arguments(dylib: dylib.path)
        // Minimal, explicit environment: nothing from the user's shell (PERL5LIB, RUBYOPT, DYLD_*).
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.qualityOfService = .utility
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    /// Launches the helper on `queue`; an interpreter that cannot be spawned ends the connection with
    /// `.launchFailed` (`onEnd`). Commands, pings and `close` sent meanwhile are queued after the launch.
    func start() {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            self.queue.async { self.consume(chunk) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // perl's loader errors name the dylib's path, which can contain the user's name.
            log.error("bridge stderr: \(String(decoding: data.prefix(512), as: UTF8.self), privacy: .private)")
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            guard let self else { return }
            self.queue.async { self.ended(status: status) }
        }
        queue.async { [self] in
            guard !closedByUs else { return }
            do { try process.run() } catch {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                onEnd(.launchFailed(error.localizedDescription))
                return
            }
            queue.asyncAfter(deadline: .now() + Self.handshakeTimeout) { [weak self] in
                guard let self, !self.gotHello, !self.closedByUs, self.process.isRunning else { return }
                log.error("bridge: no hello within \(Self.handshakeTimeout, privacy: .public) s; terminating")
                self.process.terminate()
            }
        }
    }

    /// Writes one command line ("cmd 2", "seek 30.000", "ping").
    func send(_ line: String) {
        queue.async { [self] in
            guard !closedByUs, process.isRunning else { return }
            do { try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8)) } catch {
                log.error("bridge: write failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Writes a transport command line and waits for the helper's answer: true = `ack ok`, false = refused
    /// (`ack ok:false`, `error`), nil = not written or not answered within `timeout`.
    func command(_ line: String, timeout: Duration = BridgeConnection.commandTimeout) async -> Bool? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            queue.async { [self] in
                guard !closedByUs, process.isRunning else { continuation.resume(returning: nil); return }
                do { try input.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8)) } catch {
                    log.error("bridge: write failed: \(error.localizedDescription, privacy: .private)")
                    continuation.resume(returning: nil)
                    return
                }
                let id = UUID()
                acks.append(id) { continuation.resume(returning: $0) }
                queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
                    guard let self, let waiter = self.acks.expire(id) else { return }
                    log.error("bridge: no answer to a command within \(timeout.timeInterval, privacy: .public) s")
                    waiter(nil)
                }
            }
        }
    }

    /// Round-trip time of a `ping`, or nil after `timeout`.
    func ping(timeout: Duration = .seconds(2)) async -> Duration? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Duration?, Never>) in
            queue.async { [self] in
                guard !closedByUs, process.isRunning else { continuation.resume(returning: nil); return }
                let id = UUID()
                pingWaiters.append((id, ContinuousClock.now, { continuation.resume(returning: $0) }))
                do { try input.fileHandleForWriting.write(contentsOf: Data("ping\n".utf8)) } catch {
                    finishPing(id, with: nil)
                    return
                }
                queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in self?.finishPing(id, with: nil) }
            }
        }
    }

    /// Closing stdin makes the helper exit by itself (EOF = host gone); SIGTERM after 1 s as a backstop.
    func close() {
        queue.async { [self] in
            guard !closedByUs else { return }
            closedByUs = true
            try? input.fileHandleForWriting.close()
            failWaiters()
            queue.asyncAfter(deadline: .now() + 1) { [process] in if process.isRunning { process.terminate() } }
        }
    }

    /// App termination: no time for the 1-s backstop, so close stdin and send SIGTERM right away.
    func terminateNow() {
        queue.sync {
            closedByUs = true
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            failWaiters()
        }
    }

    // MARK: - Queue-confined

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        for event in lines.append(chunk) {
            switch event {
            case .line(let line):
                guard let message = BridgeMessage.parse(line) else { continue }
                switch message {
                case .hello: gotHello = true
                case .pong: if let first = pingWaiters.first { finishPing(first.id, with: ContinuousClock.now - first.sent) }
                case .ack(let ok): acks.answerOldest()?(ok)
                case .error: acks.answerOldest()?(false)       // "bad command id", "bad position", "bad mode"
                default: break
                }
                onMessage(message)
            case .droppedLine(let bytes):
                log.error("bridge: dropped a \(bytes, privacy: .public)-byte line (artwork too large)")
            case .runaway:
                log.error("bridge: \(Self.maxDroppedBytes, privacy: .public) bytes without a newline; terminating")
                process.terminate()
            }
        }
    }

    private func ended(status: Int32) {
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        failWaiters()
        guard !closedByUs else { return }
        onEnd(gotHello ? .exited(status: status) : .noHandshake)
    }

    private func finishPing(_ id: UUID, with result: Duration?) {
        guard let index = pingWaiters.firstIndex(where: { $0.id == id }) else { return }
        pingWaiters.remove(at: index).resume(result)
    }

    /// The helper is gone or being closed: every ping and command still waiting gets "no answer".
    private func failWaiters() {
        let waiters = pingWaiters
        pingWaiters.removeAll()
        for waiter in waiters { waiter.resume(nil) }
        for waiter in acks.removeAll() { waiter(nil) }
    }
}
