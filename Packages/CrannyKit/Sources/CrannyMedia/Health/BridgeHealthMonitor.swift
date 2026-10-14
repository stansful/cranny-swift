// CrannyMedia/Health/BridgeHealthMonitor.swift — detects a silently blocked MediaRemote helper (R2 §5.4,
// ARCHITECTURE.md §6.5): another app has been producing sound for more than 10 s while the helper reports no
// elected player at all (pid 0, what a blocked helper reports) → "degraded" (Settings ▸ Media suggests the Apple
// Events fallback; diagnostics show it). What the helper reported counts, not what the UI shows: a session that
// Ignore apps or "Show media from browsers" hides, or one without a title, proves the helper works.
// One sleep to the 10-s deadline, restarted by changes; no polling.
import CrannyCore
import Foundation
import Observation
import os

private nonisolated let log = Log.logger(.media)

@MainActor @Observable final class BridgeHealthMonitor {
    static let threshold: Duration = .seconds(10)

    private(set) var isDegraded = false
    /// Another process is producing sound (Core Audio), as last reported.
    private(set) var isOutputActive = false

    @ObservationIgnored private let service: MediaService
    @ObservationIgnored private var output: AudioOutputMonitor?
    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var deadline: Task<Void, Never>?

    init(service: MediaService) { self.service = service }

    /// Starts the Core Audio listeners (`registry.onLaunch`). Tests pass `listensToCoreAudio: false` and feed
    /// `outputChanged(_:)` themselves.
    func start(listensToCoreAudio: Bool = true) {
        guard token == nil else { return }
        if listensToCoreAudio {
            let monitor = AudioOutputMonitor { [weak self] active in
                Task { @MainActor in self?.outputChanged(active) }
            }
            output = monitor
            monitor.start()
        }
        token = observe({ [weak self] in self?.suspicious ?? false }) { [weak self] _ in self?.reevaluate() }
    }

    func stop() {
        output?.stop(); output = nil
        token = nil
        deadline?.cancel(); deadline = nil
    }

    /// Fed by the Core Audio listener (and by tests).
    func outputChanged(_ active: Bool) {
        guard isOutputActive != active else { return }
        isOutputActive = active
        reevaluate()
    }

    /// Sound is playing, a bridge provider is running, and it reports no elected player (pid 0).
    private var suspicious: Bool {
        guard isOutputActive, service.reportedPlayerPID == 0 else { return false }
        switch service.status {
        case .running(.perl), .running(.ruby): return true
        default: return false
        }
    }

    private func reevaluate() {
        deadline?.cancel(); deadline = nil
        guard suspicious else {
            if isDegraded { isDegraded = false; log.info("media: helper healthy again") }
            return
        }
        guard !isDegraded else { return }
        let clock = service.clock
        deadline = Task { [weak self] in
            do { try await clock.sleep(for: Self.threshold) } catch { return }
            guard let self, self.suspicious else { return }
            self.isDegraded = true
            log.error("media: sound is playing but the helper reports nothing (degraded)")
        }
    }
}
