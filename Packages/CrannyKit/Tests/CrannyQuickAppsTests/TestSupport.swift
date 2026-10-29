// Fakes and helpers for CrannyQuickAppsTests. Nothing here launches an app or runs a shortcut: apps resolve from
// a table, the Shortcuts CLI is a closure (or a temporary shell script that never touches `/usr/bin/shortcuts`).
import AppKit
import CrannyCore
import Foundation
@testable import CrannyQuickApps

/// Apps from a table (which tests may change: "install" an app); `app(at:)` recognises "<bundle id>.app" names.
nonisolated final class FakeResolver: AppResolving, @unchecked Sendable {   // `installed` is guarded by `lock`
    private let lock = NSLock()
    private var installed: [String: ResolvedApp]

    init(_ bundleIDs: [String]) {
        installed = Dictionary(uniqueKeysWithValues: bundleIDs.map { ($0, FakeResolver.app($0)) })
    }

    static func app(_ bundleID: String) -> ResolvedApp {
        ResolvedApp(bundleID: bundleID, url: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
                    name: bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
    }

    func install(_ bundleID: String) { lock.withLock { installed[bundleID] = FakeResolver.app(bundleID) } }

    func resolve(_ bundleID: String) async -> ResolvedApp? { lock.withLock { installed[bundleID] } }
    func app(at url: URL) async -> ResolvedApp? {
        guard url.pathExtension == "app" else { return nil }
        return FakeResolver.app(url.deletingPathExtension().lastPathComponent)
    }
    func icon(at url: URL, pixelSize: Int) async -> CGImage? { nil }
}

/// Records every CLI call and answers from a closure.
nonisolated final class FakeCLI: @unchecked Sendable {   // `calls` is guarded by `lock`
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let answer: @Sendable ([String]) async throws -> CLIOutput

    init(answer: @escaping @Sendable ([String]) async throws -> CLIOutput) { self.answer = answer }

    /// `list` prints `listing`; `run` succeeds unless the id is in `failing`, and waits `runDuration` first.
    convenience init(listing: String = "", failing: Set<String> = [], runDuration: Duration = .zero) {
        self.init { arguments in
            if arguments.first == "list" { return CLIOutput(stdout: Data(listing.utf8)) }
            if runDuration > .zero { try await Task.sleep(for: runDuration) }
            if let id = arguments.last, failing.contains(id) { return CLIOutput(status: 1, stderr: Data("Error: failed".utf8)) }
            return CLIOutput()
        }
    }

    var calls: [[String]] { lock.withLock { recorded } }

    var cli: ShortcutsCLI { cli(listTimeout: ShortcutsCLI.defaultListTimeout) }

    func cli(listTimeout: Duration) -> ShortcutsCLI {
        ShortcutsCLI(executable: "/fake/shortcuts", listTimeout: listTimeout) { [self] _, arguments in
            lock.withLock { recorded.append(arguments) }
            return try await answer(arguments)
        }
    }
}

/// A wait that ignores cancellation until `open()`: a CLI that hangs and does not react to its signals. Tests open
/// it when they finish, and it opens by itself after `failSafe`, so a regression fails a test instead of hanging it.
/// A minute: tests check `!isOpen` once the answer reached them on the main actor, which other tests can keep busy
/// for longer than the 15 s this used to be (§9.6); a passing test opens it at once.
nonisolated final class Gate: @unchecked Sendable {   // `waiters`, `opened` and `cancelled` are guarded by `lock`
    static let failSafe: Duration = .seconds(60)
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    private var cancelled = false

    init() {
        Task { [weak self] in
            try? await Task.sleep(for: Gate.failSafe)
            self?.open()
        }
    }

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let now = lock.withLock { () -> Bool in
                    if !opened { waiters.append(continuation) }
                    return opened
                }
                if now { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { cancelled = true }
        }
    }

    /// Whether a waiting task was cancelled (for the live runner: the CLI was interrupted).
    var sawCancellation: Bool { lock.withLock { cancelled } }
    /// Still closed: whoever returned did not wait for the stuck operation.
    var isOpen: Bool { lock.withLock { opened } }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            opened = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in pending { waiter.resume() }
    }
}

/// A thread-safe counter: `next()` returns 1, 2, 3, …
nonisolated final class Counter: @unchecked Sendable {   // `value` is guarded by `lock`
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
    var count: Int { lock.withLock { value } }
}

/// Launches nothing; remembers what it was asked to do.
@MainActor final class RecordingLauncher: AppLaunching {
    var opened: [URL] = []
    var revealed: [URL] = []
    var failing = false
    func open(_ url: URL) async throws {
        if failing { throw QuickAppsError.appLaunchFailed }
        opened.append(url)
    }
    func reveal(_ url: URL) { revealed.append(url) }
    func openShortcutsApp() {}
}

/// A model on preview services with fakes everywhere.
@MainActor struct ModelHarness {
    let services: CrannyServices
    let model: QuickAppsModel
    let launcher: RecordingLauncher
    let cli: FakeCLI
    let center: NotificationCenter
    let resolver: FakeResolver

    var notch: PreviewNotchControl { services.notch as! PreviewNotchControl }
    var environment: PreviewSystemEnvironment { services.environment as! PreviewSystemEnvironment }

    init(installed: [String] = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music"],
         apps: [String]? = nil, shortcuts: [ShortcutEntry] = [], running: [String] = [], cli: FakeCLI = FakeCLI()) {
        services = CrannyServices.preview()
        let recorder = announced
        services.announcer = Announcer(post: { recorder.messages.append($0) })
        if let apps { services.settings[QuickAppsSettings.apps] = apps.map(AppEntry.init(bundleID:)) }
        services.settings[QuickAppsSettings.shortcuts] = shortcuts
        launcher = RecordingLauncher()
        self.cli = cli
        center = NotificationCenter()
        let center = center
        resolver = FakeResolver(installed)
        model = QuickAppsModel(services: services, resolver: resolver, launcher: launcher, cli: cli.cli,
                               running: RunningAppsObserver(center: center, snapshot: { running }))
    }

    /// VoiceOver announcements the model posted.
    let announced = Recorder()
}

/// Collects strings (announcements) on the main actor.
@MainActor final class Recorder {
    var messages: [String] = []
}

/// Apps from a table that also renders a 1 × 1 icon, so icon caching can be tested.
nonisolated struct IconResolver: AppResolving {
    func resolve(_ bundleID: String) async -> ResolvedApp? { FakeResolver.app(bundleID) }
    func app(at url: URL) async -> ResolvedApp? { nil }
    func icon(at url: URL, pixelSize: Int) async -> CGImage? {
        let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }
}

/// Polls `condition` on the main actor every 5 ms until it holds (or fails after at least `timeout`). Counted in
/// polls, not real time: a main actor kept busy by other tests delays the polls and what they wait for alike (§9.6).
@MainActor func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<Int(timeout / .milliseconds(5)) {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A temporary executable shell script (removed with its directory by the caller's `defer`).
nonisolated func makeScript(_ body: String) throws -> (url: URL, directory: URL) {
    let directory = FileManager.default.temporaryDirectory.appending(path: "cranny-quickapps-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "shortcuts")
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, directory)
}
