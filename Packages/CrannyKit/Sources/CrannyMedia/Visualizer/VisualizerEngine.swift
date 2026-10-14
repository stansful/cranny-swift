// CrannyMedia/Visualizer/VisualizerEngine.swift — decides what every visualizer draws (ARCHITECTURE.md §6.6) and
// runs the Live tap only while it is useful: the app's real service (never a sample, preview or QA service),
// mode Live, something plays (or paused < 10 s), a visualizer is on screen, and the Mac is not in Low Power Mode,
// locked or asleep. Ambient bars cost nothing here: they loop in the render server (`VisualizerLayerView`).
import CrannyCore
import Foundation
import Observation

/// What one visualizer view shows.
nonisolated enum VisualizerRender: Equatable, Sendable {
    case hidden
    /// Static 3-pt dots: paused, Static mode, Reduce Motion.
    case dots
    /// The synthetic loop for a track.
    case ambient(SyntheticSpectrum)
    /// Levels pushed by the engine (`LevelSink.receive`).
    case live
}

/// A visualizer view on screen. The engine pushes Live levels to it, outside SwiftUI (no 30-Hz invalidations).
@MainActor protocol LevelSink: AnyObject {
    func receive(levels: [Double])
}

@MainActor @Observable final class VisualizerEngine {
    enum LiveStatus: Equatable, Sendable {
        case off, waiting, receiving, silent, denied, failed, unsupported
    }

    /// 0…1 loudness for the light layer (Live only; 0 otherwise), quantized to 1/50 to limit invalidations.
    private(set) var energy: Double = 0
    private(set) var liveStatus: LiveStatus = .off

    static let pausedGrace: Duration = .seconds(10)
    static let silenceTimeout: TimeInterval = 5

    /// False for every engine except the live service's: samples show a fictional track, so their visualizers
    /// must never start the system audio tap (or its permission prompt and privacy indicator).
    let allowsLive: Bool

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let environment: any SystemEnvironment
    @ObservationIgnored private let permissions: PermissionsCenter
    @ObservationIgnored private let clock: any MediaClock
    @ObservationIgnored private var isPlaying: @MainActor () -> Bool = { false }
    @ObservationIgnored private var sinks: [ObjectIdentifier: WeakSink] = [:]
    @ObservationIgnored private var token: ObservationToken?
    @ObservationIgnored private var pausedStop: Task<Void, Never>?
    @ObservationIgnored private var live: AnyObject?          // LiveSpectrum on macOS 14.2+
    @ObservationIgnored private var lastAudio: Date?

    init(settings: SettingsStore, environment: any SystemEnvironment, permissions: PermissionsCenter, clock: any MediaClock,
         allowsLive: Bool) {
        self.settings = settings; self.environment = environment; self.permissions = permissions; self.clock = clock
        self.allowsLive = allowsLive
    }

    var mode: MediaVisualizerMode { settings[MediaSettings.visualizer] }

    /// ≤ 30 fps on AC, ≤ 20 on battery or in Low Power Mode (DESIGN.md §4.7).
    var frameRateCap: Double { environment.isOnBattery || environment.isLowPowerMode ? 20 : 30 }

    /// Wires the playback state and starts reacting to settings and the environment.
    func bind(isPlaying: @escaping @MainActor () -> Bool) {
        self.isPlaying = isPlaying
        token = observe({ [weak self] in self?.conditions ?? Conditions() }) { [weak self] _ in self?.reevaluate() }
    }

    func render(isPlaying: Bool, trackKey: String?, reduceMotion: Bool) -> VisualizerRender {
        switch mode {
        case .off: return .hidden
        case .static: return .dots
        case .ambient, .live:
            guard isPlaying, !reduceMotion else { return .dots }
            if mode == .live, allowsLive, liveStatus == .receiving { return .live }
            return .ambient(SyntheticSpectrum(trackKey: trackKey ?? ""))
        }
    }

    // MARK: Sinks (views on screen)

    /// Called from AppKit view callbacks that can run inside a SwiftUI update: the re-evaluation (which may
    /// start the tap and publish `liveStatus`) runs right after it.
    func attach(_ sink: any LevelSink) {
        sinks[ObjectIdentifier(sink)] = WeakSink(sink)
        Task { [weak self] in self?.reevaluate() }
    }

    func detach(_ sink: any LevelSink) {
        sinks[ObjectIdentifier(sink)] = nil
        Task { [weak self] in self?.reevaluate() }
    }

    var visibleCount: Int {
        sinks = sinks.filter { $0.value.sink != nil }
        return sinks.count
    }

    // MARK: Live

    /// After the why-sheet: runs the tap briefly so macOS asks for System Audio Recording now, in context.
    func requestLiveAccess() {
        guard allowsLive else { return }
        guard #available(macOS 14.2, *) else { liveStatus = .unsupported; return }
        let wasRunning = (live as? LiveSpectrum)?.isRunning ?? false
        startLive()
        guard !wasRunning else { return }
        Task { [weak self] in
            try? await self?.clock.sleep(for: .milliseconds(1500))
            self?.reevaluate()
        }
    }

    nonisolated struct Conditions: Equatable, Sendable {
        var mode = MediaVisualizerMode.ambient
        var playing = false
        var lowPower = false
        var locked = false
    }

    nonisolated enum LiveDecision: Equatable, Sendable {
        /// Start the tap (or keep it running).
        case run
        /// Paused: keep a running tap for `pausedGrace`, then stop it.
        case keepThroughPause
        case stop
    }

    /// When the tap runs (pure; ARCHITECTURE.md §6.6).
    nonisolated static func liveDecision(_ c: Conditions, allowsLive: Bool, visibleCount: Int, isRunning: Bool) -> LiveDecision {
        guard allowsLive, c.mode == .live, !c.lowPower, !c.locked, visibleCount > 0 else { return .stop }
        if c.playing { return .run }
        return isRunning ? .keepThroughPause : .stop
    }

    private var conditions: Conditions {
        Conditions(mode: mode, playing: isPlaying(), lowPower: environment.isLowPowerMode,
                   locked: environment.isScreenLocked || environment.areDisplaysAsleep)
    }

    private func reevaluate() {
        let c = conditions
        switch Self.liveDecision(c, allowsLive: allowsLive, visibleCount: visibleCount, isRunning: isLiveRunning) {
        case .run:
            pausedStop?.cancel(); pausedStop = nil
            startLive()
        case .keepThroughPause:
            guard pausedStop == nil else { return }
            pausedStop = Task { [weak self] in                       // keep the tap 10 s through a pause
                do { try await self?.clock.sleep(for: Self.pausedGrace) } catch { return }
                self?.pausedStop = nil
                self?.stopLive()
            }
        case .stop:
            pausedStop?.cancel(); pausedStop = nil
            stopLive()
            if c.mode != .live, liveStatus != .off { liveStatus = .off }
        }
    }

    private var isLiveRunning: Bool {
        guard #available(macOS 14.2, *) else { return false }
        return (live as? LiveSpectrum)?.isRunning ?? false
    }

    private func startLive() {
        guard allowsLive else { return }                              // belt and braces: samples never tap
        guard #available(macOS 14.2, *) else { liveStatus = .unsupported; return }
        let spectrum = (live as? LiveSpectrum) ?? LiveSpectrum { [weak self] frame in self?.deliver(frame) }
        live = spectrum
        guard !spectrum.isRunning else { return }
        do {
            try spectrum.start(interval: 1 / frameRateCap)
            liveStatus = .waiting
            lastAudio = clock.now
        } catch .permissionDenied {
            liveStatus = .denied
            permissions.record(.denied, for: .systemAudioRecording)
        } catch {
            liveStatus = .failed
        }
    }

    private func stopLive() {
        if #available(macOS 14.2, *) { (live as? LiveSpectrum)?.stop() }
        if energy != 0 { energy = 0 }
        if [.receiving, .waiting, .silent].contains(liveStatus) { liveStatus = .off }
    }

    @available(macOS 14.2, *)
    private func deliver(_ frame: LiveSpectrum.Frame) {
        if frame.hasAudio {
            lastAudio = clock.now
            if liveStatus != .receiving {
                liveStatus = .receiving
                permissions.record(.granted, for: .systemAudioRecording)
            }
        } else if let lastAudio, clock.now.timeIntervalSince(lastAudio) > Self.silenceTimeout, liveStatus != .silent {
            liveStatus = .silent           // denied permission delivers silence; so does a quiet passage
        }
        let quantized = (frame.energy * 50).rounded() / 50
        if quantized != energy { energy = quantized }
        guard liveStatus == .receiving else { return }
        for weak in sinks.values { weak.sink?.receive(levels: frame.bars) }
    }

    private struct WeakSink {
        weak var sink: (any LevelSink)?
        init(_ sink: any LevelSink) { self.sink = sink }
    }
}
