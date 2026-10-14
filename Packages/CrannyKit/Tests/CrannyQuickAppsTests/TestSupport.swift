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

    var cli: ShortcutsCLI {
        ShortcutsCLI(executable: "/fake/shortcuts") { [self] _, arguments in
            lock.withLock { recorded.append(arguments) }
            return try await answer(arguments)
        }
    }
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

    init(installed: [String] = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Music"],
         apps: [String]? = nil, shortcuts: [ShortcutEntry] = [], running: [String] = [], cli: FakeCLI = FakeCLI()) {
        services = CrannyServices.preview()
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
}

/// Polls `condition` on the main actor until it holds (or fails after `timeout`).
@MainActor func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
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
