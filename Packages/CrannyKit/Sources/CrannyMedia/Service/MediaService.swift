// CrannyMedia/Service/MediaService.swift — implements `NowPlayingSource` (`services.nowPlaying`, ARCHITECTURE.md
// §6.5): runs the provider chain with backoff and failover, filters sessions, debounces track changes, decodes
// artwork + palette off the main actor (LRU of 16) and applies commands optimistically. Event-driven: nothing
// polls; every delay is one sleep on the injected `MediaClock`.
import CoreGraphics
import CrannyCore
import Foundation
import Observation
import os

private nonisolated let log = Log.logger(.media)

@MainActor @Observable final class MediaService: NowPlayingSource {
    // MARK: NowPlayingSource
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: CGImage?
    private(set) var palette: AmbientPalette?
    private(set) var trackChangeCount = 0
    var audioEnergy: Double { visualizer.energy }

    // MARK: Module state
    private(set) var status: MediaProviderStatus = .idle
    private(set) var lastError: MediaError?
    /// False when the active provider can only read (title only, no transport).
    private(set) var supportsCommands = true
    /// Bundle id of the most recent visible session ("Nothing playing" shows its icon).
    private(set) var lastSourceBundleID: String?
    /// Players seen this session, newest first (offered by Settings ▸ Media ▸ Ignore apps).
    private(set) var recentSources: [String] = []

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let clock: any MediaClock
    @ObservationIgnored let visualizer: VisualizerEngine
    @ObservationIgnored private let factories: [MediaProviderFactory]
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var provider: (any MediaProvider)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var supervisor = ProviderSupervisor()
    @ObservationIgnored private var detector = TrackChangeDetector()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var artworkGrace: Task<Void, Never>?
    @ObservationIgnored private var cache = ArtworkCache()
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var raw: NowPlaying?
    @ObservationIgnored private var tokens: [ObservationToken] = []

    /// How long the previous artwork stays while the new track's artwork is on its way (60–140 ms, R2 b2).
    static let artworkGrace: Duration = .milliseconds(600)

    init(settings: SettingsStore, environment: any SystemEnvironment, permissions: PermissionsCenter,
         providers: [MediaProviderFactory], clock: any MediaClock = SystemMediaClock()) {
        self.settings = settings
        self.clock = clock
        self.factories = providers
        visualizer = VisualizerEngine(settings: settings, environment: environment, permissions: permissions, clock: clock)
        visualizer.bind { [weak self] in self?.nowPlaying?.isPlaying ?? false }
        tokens.append(observe({ [weak self] in self?.filter ?? MediaFilter() }) { [weak self] _ in self?.reapplyFilter() })
        tokens.append(observe({ settings[MediaSettings.allowAppleEvents] }) { [weak self] _ in self?.fallbackSettingChanged() })
    }

    var filter: MediaFilter {
        MediaFilter(ignoredBundleIDs: settings[MediaSettings.ignoredBundleIDs], showsBrowserMedia: settings[MediaSettings.showsBrowserMedia])
    }

    // MARK: Lifecycle

    /// Starts the chain at the first provider (`registry.onLaunch`).
    func start() {
        guard status == .idle else { return }
        supervisor.reset()
        activate(0)
    }

    /// Stops the provider and its helper (`registry.onTerminate`: synchronously, before the app exits).
    func stop() {
        generation += 1
        pump?.cancel(); pump = nil
        restartTask?.cancel(); restartTask = nil
        if let bridge = provider as? MediaRemoteBridgeProvider { bridge.terminateNow() } else { provider?.stop() }
        provider = nil
        status = .idle
    }

    /// "Retry" (widget error state, Settings ▸ Media): the whole chain again from the first provider.
    func restart() {
        lastError = nil
        supervisor.reset()
        activate(0)
    }

    // MARK: Commands

    /// Optimistic for play/pause/toggle/seek (≈ 12 ms ack; the next state, 60–75 ms later, is authoritative).
    @discardableResult func send(_ command: MediaCommand) async -> Bool {
        applyOptimistically(command)
        guard let provider, supportsCommands else { return false }
        return await provider.send(command)
    }

    /// "Test media detection": the helper's round trip, nil = no answer.
    func ping() async -> Duration? { await provider?.ping() }

    /// The kind of the provider in use (nil when none).
    var activeKind: MediaProviderKind? { status.kind }

    private func applyOptimistically(_ command: MediaCommand) {
        guard var np = nowPlaying else { return }
        let now = clock.now
        switch command {
        case .play, .pause, .togglePlayPause:
            np.elapsed = np.position(at: now)
            np.timestamp = now
            np.isPlaying = command == .play ? true : command == .pause ? false : !np.isPlaying
            if np.isPlaying, np.rate <= 0 { np.rate = 1 }
        case .seek(let target):
            np.elapsed = max(0, np.duration.map { min(target, $0) } ?? target)
            np.timestamp = now
        default:
            return
        }
        nowPlaying = np
    }

    // MARK: Provider chain

    private func activate(_ i: Int) {
        generation += 1
        let generation = generation
        pump?.cancel(); pump = nil
        restartTask?.cancel(); restartTask = nil
        provider?.stop(); provider = nil
        guard factories.indices.contains(i) else {
            index = factories.count
            status = .unavailable
            lastError = .noProvider
            supportsCommands = false
            ingest(nil)
            log.error("media: no provider available")
            return
        }
        index = i
        let factory = factories[i]
        guard factory.isEnabled() else { activate(i + 1); return }
        status = .starting(factory.kind)
        pump = Task { [weak self] in
            let made = await factory.make()
            guard let self, self.generation == generation, !Task.isCancelled else { made?.stop(); return }
            guard let made else {
                log.info("media: \(factory.kind.rawValue, privacy: .public) not available here")
                self.activate(i + 1)
                return
            }
            self.provider = made
            self.supportsCommands = made.supportsCommands
            log.info("media: provider \(factory.kind.rawValue, privacy: .public) started")
            for await event in made.start() {
                guard self.generation == generation else { break }
                self.handle(event, kind: factory.kind)
            }
        }
    }

    private func handle(_ event: ProviderEvent, kind: MediaProviderKind) {
        switch event {
        case .nowPlaying(let np):
            if status != .running(kind) { status = .running(kind) }
            ingest(np)
        case .artwork(let key, let data):
            receiveArtwork(key: key, data: data)
        case .unavailable(let failure):
            providerFailed(kind, failure)
        }
    }

    private func providerFailed(_ kind: MediaProviderKind, _ failure: ProviderFailure) {
        log.error("media: \(kind.rawValue, privacy: .public) unavailable: \(String(describing: failure), privacy: .public)")
        lastError = .provider(kind, failure)
        provider?.stop(); provider = nil
        switch supervisor.recordFailure(at: clock.now) {
        case .failover:
            supervisor.reset()
            activate(index + 1)
        case .restart(let delay):
            status = .restarting(kind)
            let generation = generation, i = index
            restartTask = Task { [weak self] in
                do { try await self?.clock.sleep(for: delay) } catch { return }
                guard let self, self.generation == generation else { return }
                self.activate(i)
            }
        }
    }

    private func fallbackSettingChanged() {
        let onFallback = status.kind == .appleScript
        if onFallback || status == .unavailable { restart() }
    }

    // MARK: Snapshots

    private func ingest(_ incoming: NowPlaying?) {
        raw = incoming
        if let source = incoming?.parentBundleID ?? incoming?.bundleID {
            recentSources.removeAll { $0 == source }
            recentSources.insert(source, at: 0)
            if recentSources.count > 8 { recentSources.removeLast() }
        }
        publish(filter.apply(incoming))
    }

    private func reapplyFilter() { publish(filter.apply(raw)) }

    private func publish(_ np: NowPlaying?) {
        let previousKey = nowPlaying?.trackKey
        if nowPlaying != np { nowPlaying = np }
        if let np, let source = np.bundleID ?? np.parentBundleID, lastSourceBundleID != source { lastSourceBundleID = source }
        if detector.observe(np) { scheduleTrackChangeDebounce() }
        if np?.trackKey != previousKey { trackDidChange(to: np?.trackKey) }
    }

    private func scheduleTrackChangeDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await self?.clock.sleep(for: TrackChangeDetector.debounce) } catch { return }
            guard let self else { return }
            if self.detector.debounceElapsed(current: self.nowPlaying) { self.trackChangeCount += 1 }
        }
    }

    // MARK: Artwork

    private func trackDidChange(to key: String?) {
        artworkGrace?.cancel(); artworkGrace = nil
        guard let key else { setArtwork(nil, key: nil); return }
        if let hit = cache.value(for: key) { setArtwork(hit, key: key); return }
        // Keep the previous artwork briefly: the new one usually follows the state within ≈ 100 ms.
        artworkGrace = Task { [weak self] in
            do { try await self?.clock.sleep(for: Self.artworkGrace) } catch { return }
            guard let self, self.nowPlaying?.trackKey == key, self.artworkKey != key else { return }
            self.setArtwork(nil, key: nil)
        }
    }

    private func receiveArtwork(key: String, data: Data) {
        if let hit = cache.value(for: key) {
            if key == nowPlaying?.trackKey, artworkKey != key { setArtwork(hit, key: key) }
            return
        }
        Task { [weak self] in
            guard let decoded = await ArtworkDecoder.decode(data), let self else { return }
            self.cache.insert(decoded, for: key)
            // Late artwork for the current track is applied; artwork for another track only fills the cache.
            if key == self.nowPlaying?.trackKey { self.setArtwork(decoded, key: key) }
        }
    }

    private func setArtwork(_ decoded: DecodedArtwork?, key: String?) {
        artworkGrace?.cancel(); artworkGrace = nil
        artworkKey = key
        artwork = decoded?.image
        palette = decoded?.palette
    }

    // MARK: Previews, stages and Debug QA

    /// Shows a fixed session without any provider (sample activity, `#Preview`, `--qa-media`).
    func seed(_ np: NowPlaying?, artwork decoded: DecodedArtwork?) {
        if let decoded, let key = np?.trackKey { cache.insert(decoded, for: key) }
        raw = np
        nowPlaying = np
        lastSourceBundleID = np?.bundleID ?? lastSourceBundleID
        setArtwork(decoded, key: np?.trackKey)
        status = np == nil ? .idle : .running(.sample)
    }
}
