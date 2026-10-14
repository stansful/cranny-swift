// Visualizer logic: the synthetic spectrum (determinism, range, seamless loop, rest), the FFT analyzer on synthetic
// buffers (no audio tap is ever started), the energy follower and the sample ring.
import CrannyCore
import Foundation
import Testing
@testable import CrannyMedia

@Suite("Synthetic spectrum") struct SyntheticSpectrumTests {
    @Test func deterministicPerTrackKey() {
        let a = SyntheticSpectrum(trackKey: "spotify:track:42"), b = SyntheticSpectrum(trackKey: "spotify:track:42")
        #expect(a == b)
        #expect(a.seed == SyntheticSpectrum.fnv1a("spotify:track:42"))
        for bar in 0..<SyntheticSpectrum.barCount {
            #expect(a.keyframes(bar: bar, fps: 30) == b.keyframes(bar: bar, fps: 30))
        }
        let other = SyntheticSpectrum(trackKey: "spotify:track:43")
        #expect(a.keyframes(bar: 2, fps: 30) != other.keyframes(bar: 2, fps: 30))
    }

    @Test func fnvIsStableAcrossLaunches() {
        // Fixed reference values: `hashValue` would change every launch.
        #expect(SyntheticSpectrum.fnv1a("") == 0xcbf2_9ce4_8422_2325)
        #expect(SyntheticSpectrum.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test(arguments: ["", "a", "Midnight Window", "com.apple.Music|Song|Artist|Album"])
    func tempoAndRange(_ key: String) {
        let s = SyntheticSpectrum(trackKey: key)
        #expect([100.0, 105, 110, 115, 120].contains(s.bpm))
        #expect((8...9.6).contains(s.loopDuration))
        for bar in 0..<SyntheticSpectrum.barCount {
            for frame in s.keyframes(bar: bar, fps: 30) {
                #expect(frame >= SyntheticSpectrum.floor && frame <= SyntheticSpectrum.ceiling)
            }
        }
    }

    @Test func loopsSeamlessly() {
        let s = SyntheticSpectrum(trackKey: "loop")
        for bar in 0..<SyntheticSpectrum.barCount {
            for t in stride(from: 0.0, to: s.loopDuration, by: 0.37) {
                #expect(abs(s.level(bar: bar, at: t) - s.level(bar: bar, at: t + s.loopDuration)) < 1e-9)
            }
        }
    }

    @Test func keyframesSampleOneLoop() {
        let s = SyntheticSpectrum(trackKey: "frames")
        let frames = s.keyframes(bar: 0, fps: 30)
        #expect(frames.count == Int((s.loopDuration * 30).rounded()))
        #expect(frames.first == s.level(bar: 0, at: 0))
        #expect(s.keyframes(bar: 0, fps: 20).count < frames.count)        // battery: fewer frames
        #expect(s.level(bar: 99, at: 1) == SyntheticSpectrum.floor)        // out of range: resting floor
    }

    @Test func barsMove() {
        let s = SyntheticSpectrum(trackKey: "moves")
        for bar in 0..<SyntheticSpectrum.barCount {
            let frames = s.keyframes(bar: bar, fps: 30)
            #expect((frames.max() ?? 0) - (frames.min() ?? 0) > 0.3)       // visibly alive, not a flat line
        }
    }

    @Test func easesToRestIn400Milliseconds() {
        #expect(SyntheticSpectrum.restEnvelope(elapsed: 0) == 1)
        #expect(SyntheticSpectrum.restEnvelope(elapsed: -1) == 1)
        #expect(SyntheticSpectrum.restEnvelope(elapsed: 0.4) == 0)
        #expect(SyntheticSpectrum.restEnvelope(elapsed: 5) == 0)
        var previous = 1.0
        for ms in stride(from: 20, through: 400, by: 20) {
            let value = SyntheticSpectrum.restEnvelope(elapsed: Double(ms) / 1000)
            #expect(value < previous)
            previous = value
        }
    }

    @Test func metricsMapLevelsToHeights() {
        let m = VisualizerMetrics.compact(unit: 1)
        #expect(m.width == 23)                                             // 5 × 3 + 4 × 2
        #expect(m.height(for: 0) == 4)
        #expect(m.height(for: 1) == 16)
        #expect(m.height(for: 2) == 16)
        #expect(m.dot == 3)
    }
}

@Suite("Spectrum analyzer") struct SpectrumAnalyzerTests {
    private func sine(_ hz: Double, amplitude: Float = 0.5, count: Int = 1024, rate: Double = 48_000) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func analyze(_ samples: [Float], frames: Int = 12) throws -> SpectrumAnalyzer {
        let analyzer = try #require(SpectrumAnalyzer())
        for _ in 0..<frames { samples.withUnsafeBufferPointer { analyzer.analyze($0) } }
        return analyzer
    }

    @Test func silenceIsZero() throws {
        let analyzer = try analyze([Float](repeating: 0, count: 1024))
        #expect(analyzer.bands.allSatisfy { $0 == 0 })
        #expect(analyzer.barLevels.allSatisfy { $0 == 0 })
    }

    // Bars: ≈ 40–85 Hz · 85–300 Hz · 300 Hz–1 kHz · 1–3.6 kHz · 3.6–16 kHz (24 log bands folded 3/5/5/5/6).
    @Test(arguments: [(200.0, 1), (600.0, 2), (2_000.0, 3), (8_000.0, 4)])
    func toneLandsInTheRightBar(_ hz: Double, _ bar: Int) throws {
        let analyzer = try analyze(sine(hz))
        let levels = analyzer.barLevels
        #expect(levels.count == 5)
        #expect(levels.indices.max { levels[$0] < levels[$1] } == bar)
        #expect(levels[bar] > 0.5)
    }

    @Test func louderIsHigher() throws {
        let quiet = try analyze(sine(1_000, amplitude: 0.01)).barLevels[2]
        let loud = try analyze(sine(1_000, amplitude: 0.8)).barLevels[2]
        #expect(loud > quiet)
    }

    @Test func wrongBufferSizeIsIgnored() throws {
        let analyzer = try #require(SpectrumAnalyzer())
        [Float](repeating: 1, count: 512).withUnsafeBufferPointer { analyzer.analyze($0) }
        #expect(analyzer.bands.allSatisfy { $0 == 0 })
        #expect(SpectrumAnalyzer(size: 8) == nil)
    }

    @Test func rms() {
        let square = [Float](repeating: 0.5, count: 256)
        #expect(abs(square.withUnsafeBufferPointer(SpectrumAnalyzer.rms) - 0.5) < 1e-6)
        let tone = sine(440, amplitude: 1, count: 4800)
        #expect(abs(tone.withUnsafeBufferPointer(SpectrumAnalyzer.rms) - Float(1 / 2.0.squareRoot())) < 0.01)
        #expect([Float]().withUnsafeBufferPointer(SpectrumAnalyzer.rms) == 0)
    }

    @Test func foldGroupsBandsIntoFiveBars() {
        var levels = [Double](repeating: 0, count: 24)
        levels[0] = 0.9; levels[23] = 0.4
        #expect(SpectrumAnalyzer.fold(levels, into: 5) == [0.9, 0, 0, 0, 0.4])
        #expect(SpectrumAnalyzer.fold([], into: 5) == [0, 0, 0, 0, 0])
        #expect(SpectrumAnalyzer.fold([0.1, 0.2], into: 5).count == 5)
    }
}

@Suite("Energy and samples") struct EnergyTests {
    @Test func attackIsFasterThanRelease() {
        var follower = EnergyFollower()
        let afterAttack = follower.update(rms: 0.4, dt: 0.06)              // one attack time constant
        #expect(abs(afterAttack - (1 - exp(-1))) < 1e-9)
        var steady = EnergyFollower()
        for _ in 0..<100 { _ = steady.update(rms: 0.4, dt: 1.0 / 30) }
        #expect(abs(steady.value - 1) < 1e-6)                             // 0.4 RMS is loud music → 1
        let afterRelease = steady.update(rms: 0, dt: 0.06)
        #expect(afterRelease > 0.8)                                        // 300-ms release: slow fall
        #expect(follower.update(rms: 0.2, dt: 0) == afterAttack)           // dt 0: unchanged
    }

    @Test func ringReturnsTheLatestSamplesOldestFirst() {
        let ring = SampleRing(capacity: 64)
        let first = (0..<50).map(Float.init), second = (50..<80).map(Float.init)
        first.withUnsafeBufferPointer { ring.pushMono($0) }
        second.withUnsafeBufferPointer { ring.pushMono($0) }
        var out = [Float](repeating: -1, count: 8)
        let written = out.withUnsafeMutableBufferPointer { ring.latest(into: $0) }
        #expect(written == 80)
        #expect(out == (72..<80).map(Float.init))
    }

    @Test func stereoIsMixedToMono() {
        let ring = SampleRing(capacity: 64)
        let stereo: [Float] = [1, 0, 0.5, 0.5, -1, 1]
        stereo.withUnsafeBufferPointer { ring.pushStereo($0.baseAddress!, frames: 3) }
        var out = [Float](repeating: 9, count: 3)
        out.withUnsafeMutableBufferPointer { _ = ring.latest(into: $0) }
        #expect(out == [0.5, 0.5, 0])
    }
}

/// Stands in for `LiveSpectrum`: records what the engine asks for and never touches Core Audio.
@MainActor final class FakeLiveSource: LiveLevelSource {
    private(set) var starts = 0
    private(set) var stops = 0
    /// Seconds per frame the loop would run at now (nil = never started).
    private(set) var interval: Double?
    private(set) var isRunning = false
    var failure: SystemAudioTapError?
    let onFrame: @MainActor (LiveFrame) -> Void

    init(onFrame: @escaping @MainActor (LiveFrame) -> Void) { self.onFrame = onFrame }

    func start(interval: Double) throws(SystemAudioTapError) {
        if let failure { throw failure }
        starts += 1
        isRunning = true
        self.interval = interval
    }
    func retune(interval: Double) { self.interval = interval }
    func stop() {
        if isRunning { stops += 1 }
        isRunning = false
    }
}

@MainActor final class RecordingSink: LevelSink {
    private(set) var levels: [[Double]] = []
    func receive(levels: [Double]) { self.levels.append(levels) }
}

@Suite("Visualizer engine") @MainActor struct VisualizerEngineTests {
    /// Every engine here gets fake Live sources (`sources`): tests never start the system audio tap.
    private final class Sources {
        var made: [FakeLiveSource] = []
        var failure: SystemAudioTapError?
    }

    private final class Player {
        var isPlaying = true
    }

    private func engine(_ mode: MediaVisualizerMode, environment: PreviewSystemEnvironment = PreviewSystemEnvironment(),
                        allowsLive: Bool = true) -> (VisualizerEngine, SettingsStore, Sources) {
        let services = CrannyServices.preview(environment: environment)
        services.settings[MediaSettings.visualizer] = mode
        let sources = Sources()
        let engine = VisualizerEngine(settings: services.settings, environment: services.environment,
                                      permissions: services.permissions, clock: ManualClock(), allowsLive: allowsLive) { onFrame in
            let source = FakeLiveSource(onFrame: onFrame)
            source.failure = sources.failure
            sources.made.append(source)
            return source
        }
        return (engine, services.settings, sources)
    }

    @Test func whatEachModeDraws() {
        let (e, settings, _) = engine(.ambient)
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .ambient(SyntheticSpectrum(trackKey: "k")))
        #expect(e.render(isPlaying: false, trackKey: "k", reduceMotion: false) == .dots)       // paused → static
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: true) == .dots)         // Reduce Motion → static
        settings[MediaSettings.visualizer] = .static
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .dots)
        settings[MediaSettings.visualizer] = .off
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .hidden)
        settings[MediaSettings.visualizer] = .live
        // Until the tap delivers sound, Live shows the honest ambient pattern.
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .ambient(SyntheticSpectrum(trackKey: "k")))
        #expect(e.liveStatus == .off)
        #expect(e.energy == 0)
    }

    @Test func frameRateFollowsPower() {
        let environment = PreviewSystemEnvironment()
        let (e, _, _) = engine(.ambient, environment: environment)
        #expect(e.frameRateCap == 30)
        environment.isOnBattery = true
        #expect(e.frameRateCap == 20)
        environment.isOnBattery = false
        environment.isLowPowerMode = true
        #expect(e.frameRateCap == 20)
    }

    @Test func whenTheTapRuns() {
        typealias C = VisualizerEngine.Conditions
        let decide = VisualizerEngine.liveDecision
        let live = C(mode: .live, playing: true)
        #expect(decide(live, true, 1, false) == .run)
        #expect(decide(live, false, 1, false) == .stop)                   // samples, previews, QA: never
        #expect(decide(live, true, 0, false) == .stop)                    // no visualizer on screen
        #expect(decide(C(mode: .ambient, playing: true), true, 1, false) == .stop)
        #expect(decide(C(mode: .live, playing: true, lowPower: true), true, 1, true) == .stop)
        #expect(decide(C(mode: .live, playing: true, locked: true), true, 1, true) == .stop)
        let paused = C(mode: .live, playing: false)
        #expect(decide(paused, true, 1, true) == .keepThroughPause)       // 10 s through a pause …
        #expect(decide(paused, true, 1, false) == .stop)                  // … but never started by a pause
        #expect(decide(paused, false, 1, true) == .stop)
    }

    @Test func enginesThatMayNotTapNeverRenderLive() async {
        let (e, _, sources) = engine(.live, allowsLive: false)
        e.bind(isPlaying: { true })
        await settle()
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .ambient(SyntheticSpectrum(trackKey: "k")))
        e.requestLiveAccess()
        await settle()
        #expect(e.liveStatus == .off)
        #expect(sources.made.isEmpty)
    }

    @Test func liveNeverStartsWithoutAVisibleVisualizer() async {
        // Mode Live and playing, but no visualizer on screen: the tap (and its permission prompt) never starts.
        let (e, _, sources) = engine(.live)
        e.bind(isPlaying: { true })
        await settle()
        #expect(e.liveStatus == .off)
        #expect(e.visibleCount == 0)
        #expect(sources.made.isEmpty)
    }

    @Test func liveRunsWhileAVisualizerIsOnScreenAndPushesLevels() async throws {
        let (e, _, sources) = engine(.live)
        e.bind(isPlaying: { true })
        let sink = RecordingSink()
        e.attach(sink)
        await settle()
        let live = try #require(sources.made.first)
        #expect(live.starts == 1)
        #expect(live.interval == 1.0 / 30)
        #expect(e.liveStatus == .waiting)

        live.onFrame(LiveFrame(bars: [0.1, 0.2, 0.3, 0.4, 0.5], energy: 0.403, hasAudio: true))
        #expect(e.liveStatus == .receiving)
        #expect(e.energy == 0.4)                                          // quantized to 1/50
        #expect(sink.levels == [[0.1, 0.2, 0.3, 0.4, 0.5]])
        #expect(e.render(isPlaying: true, trackKey: "k", reduceMotion: false) == .live)

        e.detach(sink)
        await settle()
        #expect(!live.isRunning)                                          // nothing on screen: the tap stops
        #expect(e.liveStatus == .off)
        #expect(e.energy == 0)
    }

    @Test func runningLiveLoopFollowsThePowerSource() async throws {
        // Opted in on AC (30 fps), then the charger is unplugged: ≤ 20 fps on battery (DESIGN.md §4.7). The loop is
        // retuned in place: one tap, no restart (no second aggregate device, no privacy-indicator flicker).
        let environment = PreviewSystemEnvironment()
        let (e, _, sources) = engine(.live, environment: environment)
        let player = Player()
        e.bind(isPlaying: { player.isPlaying })
        let sink = RecordingSink()
        e.attach(sink)
        await settle()
        let live = try #require(sources.made.first)
        #expect(live.interval == 1.0 / 30)

        environment.isOnBattery = true
        await settle()
        #expect(live.interval == 1.0 / 20)
        #expect(live.isRunning)
        #expect(live.starts == 1)
        #expect(live.stops == 0)

        environment.isOnBattery = false
        await settle()
        #expect(live.interval == 1.0 / 30)

        // Kept through a pause (10 s), the loop still follows the power source.
        player.isPlaying = false                                          // not observed: the battery change re-evaluates
        environment.isOnBattery = true
        await settle()
        #expect(live.isRunning)
        #expect(live.interval == 1.0 / 20)
        #expect(live.starts == 1)
        #expect(sources.made.count == 1)
        withExtendedLifetime(sink) {}
    }

    @Test func lowPowerModeStopsALiveTap() async throws {
        let environment = PreviewSystemEnvironment()
        let (e, _, sources) = engine(.live, environment: environment)
        e.bind(isPlaying: { true })
        let sink = RecordingSink()
        e.attach(sink)
        await settle()
        let live = try #require(sources.made.first)
        #expect(live.isRunning)
        environment.isLowPowerMode = true
        await settle()
        #expect(!live.isRunning)
        #expect(live.stops == 1)
        #expect(e.liveStatus == .off)
        environment.isLowPowerMode = false
        await settle()
        #expect(live.isRunning)
        #expect(live.starts == 2)
        #expect(live.interval == 1.0 / 30)
        withExtendedLifetime(sink) {}
    }

    @Test func deniedTapIsReported() async throws {
        let (e, _, sources) = engine(.live)
        sources.failure = .permissionDenied
        e.bind(isPlaying: { true })
        let sink = RecordingSink()
        e.attach(sink)
        await settle()
        #expect(e.liveStatus == .denied)
        #expect(sources.made.count == 1)
        withExtendedLifetime(sink) {}
    }

    @Test func noLiveSourceMeansUnsupported() async {
        let services = CrannyServices.preview()
        services.settings[MediaSettings.visualizer] = .live
        let e = VisualizerEngine(settings: services.settings, environment: services.environment,
                                 permissions: services.permissions, clock: ManualClock(), allowsLive: true) { _ in nil }
        e.requestLiveAccess()
        await settle()
        #expect(e.liveStatus == .unsupported)
    }
}
