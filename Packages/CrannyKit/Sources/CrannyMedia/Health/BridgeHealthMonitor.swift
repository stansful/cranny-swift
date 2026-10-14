// CrannyMedia/Health/BridgeHealthMonitor.swift — detects a silently blocked MediaRemote helper (R2 §5.4,
// ARCHITECTURE.md §6.5): another app has been producing sound for more than 10 s while the helper reports no
// elected player at all (pid 0, what a blocked helper reports) → "degraded" (Settings ▸ Media suggests the Apple
// Events fallback; diagnostics show it). What the helper reported counts, not what the UI shows: a session that
// Ignore apps or "Show media from browsers" hides, or one without a title, proves the helper works.
// One sleep to the 10-s deadline, restarted by changes; no polling. The Core Audio listeners are armed only while
// their answer can matter (a bridge provider runs and reports no elected player): while a player is elected — Music
// or Spotify open, even paused — or another provider runs, other apps' sounds wake nothing here.
import CrannyCore
import Foundation
import Observation
import os

private nonisolated let log = Log.logger(.media)

@MainActor @Observable final class BridgeHealthMonitor {
    static let threshold: Duration = .seconds(10)

    private(set) var isDegraded = false
    /// Another process is producing sound (Core Audio), as last reported while the listeners were armed (false
    /// while they are not).
    private(set) var isOutputActive = false

    @ObservationIgnored private let service: MediaService
    @ObservationIgnored private var makeMonitor: OutputMonitorFactory?
    @ObservationIgnored private var output: (any OutputMonitoring)?
    /// Counts armings: a report from a monitor that was disarmed meanwhile is dropped.
    @ObservationIgnored private var arming = 0
    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var armToken: ObservationToken?
    @ObservationIgnored private var deadline: Task<Void, Never>?

    /// Makes the monitor that reports other apps' sound to its argument (Core Audio in the app).
    typealias OutputMonitorFactory = @MainActor (_ onChange: @escaping @Sendable (Bool) -> Void) -> any OutputMonitoring

    init(service: MediaService) { self.service = service }

    /// Starts watching (`registry.onLaunch`); the Core Audio listeners follow `needsCoreAudio`. Tests pass
    /// `listensToCoreAudio: false` and feed `outputChanged(_:)` themselves, or a fake `makeMonitor`.
    func start(listensToCoreAudio: Bool = true,
               makeMonitor: @escaping OutputMonitorFactory = { AudioOutputMonitor(onChange: $0) }) {
        guard token == nil else { return }
        if listensToCoreAudio {
            self.makeMonitor = makeMonitor
            armToken = observe({ [weak self] in self?.needsCoreAudio ?? false }) { [weak self] in self?.setListening($0) }
            setListening(needsCoreAudio)
        }
        token = observe({ [weak self] in self?.suspicious ?? false }) { [weak self] _ in self?.reevaluate() }
    }

    /// The Core Audio listeners are armed.
    var isListening: Bool { output != nil }

    func stop() {
        armToken = nil
        setListening(false)
        token = nil
        deadline?.cancel(); deadline = nil
    }

    /// For diagnostics: the listeners' last report while they are armed (or what a test fed), else a one-off read.
    var reportsOutputActive: Bool {
        guard makeMonitor != nil, output == nil else { return isOutputActive }
        return AudioOutputMonitor.isOtherProcessRunningOutput()
    }

    /// Fed by the Core Audio listener (and by tests).
    func outputChanged(_ active: Bool) {
        guard isOutputActive != active else { return }
        isOutputActive = active
        reevaluate()
    }

    /// Sound is playing, a bridge provider is running, and it reports no elected player (pid 0).
    private var suspicious: Bool { isOutputActive && needsCoreAudio }

    /// A bridge provider is running and reports no elected player (pid 0): only then can sound make it suspicious.
    private var needsCoreAudio: Bool {
        guard service.reportedPlayerPID == 0 else { return false }
        switch service.status {
        case .running(.perl), .running(.ruby): return true
        default: return false
        }
    }

    /// Arms or disarms the Core Audio listeners. An armed monitor reports the current answer at once, so the 10-s
    /// deadline starts when the bridge's report makes sound matter, as if they had listened all along.
    private func setListening(_ listening: Bool) {
        guard listening != isListening, let makeMonitor else { return }
        arming += 1
        if listening {
            let arming = arming
            let monitor = makeMonitor { [weak self] active in
                Task { @MainActor in self?.outputReported(active, arming: arming) }
            }
            output = monitor
            monitor.start()
        } else {
            output?.stop(); output = nil
            if isOutputActive { isOutputActive = false }               // unknown while nobody listens
        }
    }

    private func outputReported(_ active: Bool, arming: Int) {
        guard arming == self.arming, output != nil else { return }
        outputChanged(active)
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
