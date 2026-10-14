// CrannyAppShell/App/LaunchGate.swift — pairs the modules' launch and terminate hooks (ARCHITECTURE.md §3.4). A module's
// terminate hook writes what its launch hook restored (Timer saves its state, Tray empties its work folder), so it
// must never run when the launch hooks did not: `--diagnostics` quits without launching any module, and a quit that
// arrives while the launch hooks are still running waits for them (up to `quitWait`) before the hooks run.
import Foundation

@MainActor final class LaunchGate {
    enum Phase: Equatable { case notLaunched, launching, launched }

    /// The longest a quit waits for the launch hooks (they read a few small files; a hung one must not block quitting).
    static let quitWait: Duration = .seconds(3)

    private(set) var phase = Phase.notLaunched
    private var pendingQuit: (() -> Void)?
    private var quitTimeout: Task<Void, Never>?

    /// Runs `hooks` (the registry's launch hooks) once.
    func launch(_ hooks: @escaping @MainActor () async -> Void) {
        guard phase == .notLaunched else { return }
        phase = .launching
        Task {
            await hooks()
            self.phase = .launched
            self.releaseQuit()
        }
    }

    /// Whether `applicationWillTerminate` may run the terminate hooks: only after a launch (never in `--diagnostics`).
    var runsTerminateHooks: Bool { phase != .notLaunched }

    /// `applicationShouldTerminate`: true when the quit must wait; `reply` is then called once, when the launch hooks
    /// finished or `limit` passed, whichever comes first. A second request while one waits shares its reply.
    func defersQuit(atMost limit: Duration = LaunchGate.quitWait, reply: @escaping () -> Void) -> Bool {
        guard phase == .launching else { return false }
        guard pendingQuit == nil else { return true }
        pendingQuit = reply
        quitTimeout = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            self?.releaseQuit()
        }
        return true
    }

    private func releaseQuit() {
        quitTimeout?.cancel()
        quitTimeout = nil
        let reply = pendingQuit
        pendingQuit = nil
        reply?()
    }
}
