// CrannyMedia/Visualizer/VisualizerEngine.swift — decides what every visualizer draws (ARCHITECTURE.md §6.6) and
// runs the Live tap only while it is useful: the app's real service (never a sample, preview or QA service),
// mode Live, something plays (or paused < 10 s), a visualizer that uses levels is on screen (`wantsLevels`: bars
// that can move, or the widget's, whose loudness also lights the panel; Reduce Motion rests the compact bars, so
// they never start the tap), and the Mac is not in Low Power Mode, locked or asleep. A running tap follows the
// frame-rate cap: plugging or unplugging the charger retunes its analysis loop (30 ↔ 20 fps) without restarting the
// tap. While nothing the loop computes is shown (the tap hears only silence, or the player is paused and the tap
// hears nothing) the loop drops to a 4-Hz probe that notices sound coming back. A tap that could not start (denied,
// a Core Audio error) is tried again after 30 s at the earliest, not on every panel open; asking for access (the
// why-sheet) or choosing Live again tries at once. Ambient bars cost nothing here: they loop in the render server
// (`VisualizerLayerView`).
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

/// A visualizer view on screen that uses Live levels (`wantsLevels`). The engine pushes them to it, outside SwiftUI
/// (no 30-Hz invalidations).
@MainActor protocol LevelSink: AnyObject {
    func receive(levels: [Double])
}

/// What one Live analysis frame produced.
nonisolated struct LiveFrame: Equatable, Sendable {
    var bars: [Double]
    var energy: Double
    /// False while the tap delivers digital silence (denied permission, muted output, a quiet passage).
    var hasAudio: Bool
}

/// The Live tap and its analysis loop, as the engine drives them: `LiveSpectrum` in the app, a recording fake in
/// tests (tests never start the system audio tap or its permission prompt).
@MainActor protocol LiveLevelSource: AnyObject {
    /// From `start` until `stop` or a reported failure (also while the tap is still starting).
    var isRunning: Bool { get }
    /// Starts the tap (prompting the first time) off the main thread, then the analysis loop at `interval` seconds
    /// per frame. `onStart` tells (on the main actor) whether the tap started; after a failure the source is
    /// stopped. A start that `stop` overtook still reports a failure (unless a newer start is on its way), never a
    /// success.
    func start(interval: Double, onStart: @escaping @MainActor (Result<Void, SystemAudioTapError>) -> Void)
    /// Changes the running loop's frame interval from its next frame on (at once when shorter). The tap keeps running.
    func retune(interval: Double)
    func stop()
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
    /// Seconds per analysis frame while nothing the loop computes is shown: enough to notice sound coming back.
    static let probeInterval = 0.25
    /// A tap that could not start is tried again after this long at the earliest: each try builds and tears down a
    /// process tap and an aggregate device in coreaudiod.
    static let retryAfter: TimeInterval = 30

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
    @ObservationIgnored private let makeLiveSource: LiveSourceFactory
    @ObservationIgnored private var live: (any LiveLevelSource)?    // created on the first start
    @ObservationIgnored private var lastAudio: Date?
    /// When the last start failed (nil after any other start): automatic retries wait `retryAfter`.
    @ObservationIgnored private var lastFailedStart: Date?
    /// The last frame heard nothing and the energy has decayed to 0.
    @ObservationIgnored private var idleFrames = false

    /// Makes the Live source that calls back with every frame; nil = the system cannot tap (before macOS 14.2).
    typealias LiveSourceFactory =
        @MainActor (_ onFrame: @escaping @MainActor (LiveFrame) -> Void) -> (any LiveLevelSource)?

    init(settings: SettingsStore, environment: any SystemEnvironment, permissions: PermissionsCenter, clock: any MediaClock,
         allowsLive: Bool, makeLiveSource: @escaping LiveSourceFactory = VisualizerEngine.systemLiveSource) {
        self.settings = settings; self.environment = environment; self.permissions = permissions; self.clock = clock
        self.allowsLive = allowsLive
        self.makeLiveSource = makeLiveSource
    }

    /// The system audio tap + FFT loop (macOS 14.2+).
    static func systemLiveSource(onFrame: @escaping @MainActor (LiveFrame) -> Void) -> (any LiveLevelSource)? {
        guard #available(macOS 14.2, *) else { return nil }
        return LiveSpectrum(onFrame: onFrame)
    }

    var mode: MediaVisualizerMode { settings[MediaSettings.visualizer] }

    /// ≤ 30 fps on AC, ≤ 20 on battery or in Low Power Mode (DESIGN.md §4.7). Ambient bars and the Live loop alike.
    var frameRateCap: Double { environment.isOnBattery || environment.isLowPowerMode ? 20 : 30 }

    /// Wires the playback state and starts reacting to settings and the environment.
    func bind(isPlaying: @escaping @MainActor () -> Bool) {
        self.isPlaying = isPlaying
        token = observe({ [weak self] in self?.conditions ?? Conditions() }) { [weak self] _ in self?.reevaluate() }
    }

    /// Whether a visualizer on screen uses Live levels, so its view registers as a sink (`attach`): mode Live on an
    /// engine that may tap, with bars that can move, or bars that feed the light (`feedsLight`: the widget's, whose
    /// tap drives `energy` even while Reduce Motion rests them). The others never start the tap or re-evaluate.
    func wantsLevels(reduceMotion: Bool, feedsLight: Bool) -> Bool {
        allowsLive && mode == .live && (!reduceMotion || feedsLight)
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

    /// After the why-sheet: runs the tap briefly so macOS asks for System Audio Recording now, in context (also
    /// right after a failed start).
    func requestLiveAccess() {
        guard allowsLive else { return }
        let wasRunning = isLiveRunning
        startLive(force: true)
        guard !wasRunning, liveStatus != .unsupported else { return }
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
        /// `frameRateCap`: not part of the decision, but a change (charger plugged or unplugged) re-evaluates, and the
        /// re-evaluation retunes a running loop.
        var frameRate: Double = 30
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
                   locked: environment.isScreenLocked || environment.areDisplaysAsleep, frameRate: frameRateCap)
    }

    private func reevaluate() {
        let c = conditions
        switch Self.liveDecision(c, allowsLive: allowsLive, visibleCount: visibleCount, isRunning: isLiveRunning) {
        case .run:
            pausedStop?.cancel(); pausedStop = nil
            startLive()
        case .keepThroughPause:
            retuneLive()
            guard pausedStop == nil else { return }
            pausedStop = Task { [weak self] in                       // keep the tap 10 s through a pause
                do { try await self?.clock.sleep(for: Self.pausedGrace) } catch { return }
                self?.pausedStop = nil
                self?.stopLive()
            }
        case .stop:
            pausedStop?.cancel(); pausedStop = nil
            stopLive()
            if c.mode != .live {
                lastFailedStart = nil                                 // choosing Live again tries at once
                if liveStatus != .off { liveStatus = .off }
            }
        }
    }

    private var isLiveRunning: Bool { live?.isRunning ?? false }

    /// The analysis loop's frame interval: the frame-rate cap, or the probe while nothing the loop computes is shown
    /// (silence: Ambient bars and no energy; paused with nothing heard: dots and no energy).
    private var liveInterval: Double {
        liveStatus == .silent || (idleFrames && !isPlaying()) ? Self.probeInterval : 1 / frameRateCap
    }

    /// Starts the tap at the current frame-rate cap, or retunes a running one to it. After a failed start it waits
    /// `retryAfter` unless `force`d (the why-sheet).
    private func startLive(force: Bool = false) {
        guard allowsLive else { return }                              // belt and braces: samples never tap
        guard let source = live ?? makeLiveSource({ [weak self] frame in self?.deliver(frame) }) else {
            liveStatus = .unsupported
            return
        }
        live = source
        guard !source.isRunning else { source.retune(interval: liveInterval); return }
        if !force, let lastFailedStart, clock.now.timeIntervalSince(lastFailedStart) < Self.retryAfter { return }
        lastFailedStart = nil
        source.start(interval: liveInterval) { [weak self] outcome in self?.liveStarted(outcome) }
    }

    /// The tap queue's answer. Until it comes the status stays what it was (a retry after a denial keeps showing
    /// "denied" instead of flashing "waiting"). A tap that could not start: the status says why, render() keeps
    /// drawing Ambient, and no automatic retry for `retryAfter`.
    private func liveStarted(_ outcome: Result<Void, SystemAudioTapError>) {
        switch outcome {
        case .success:
            liveStatus = .waiting
            lastAudio = clock.now
        case .failure(let error):
            guard mode == .live else { return }                       // the user has left Live since: nothing to show
            lastFailedStart = clock.now
            switch error {
            case .permissionDenied:
                liveStatus = .denied
                permissions.record(.denied, for: .systemAudioRecording)
            case .coreAudio:
                liveStatus = .failed
            }
        }
    }

    /// A running tap follows the frame-rate cap (≤ 20 fps on battery) while it is kept through a pause, too.
    private func retuneLive() {
        guard let live, live.isRunning else { return }
        live.retune(interval: liveInterval)
    }

    private func stopLive() {
        live?.stop()
        idleFrames = false
        if energy != 0 { energy = 0 }
        if [.receiving, .waiting, .silent].contains(liveStatus) { liveStatus = .off }
    }

    private func deliver(_ frame: LiveFrame) {
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
        idleFrames = !frame.hasAudio && quantized == 0
        if let live, live.isRunning { live.retune(interval: liveInterval) }   // probe ↔ frame rate; no-op if unchanged
        guard liveStatus == .receiving else { return }
        for weak in sinks.values { weak.sink?.receive(levels: frame.bars) }
    }

    private struct WeakSink {
        weak var sink: (any LevelSink)?
        init(_ sink: any LevelSink) { self.sink = sink }
    }
}
