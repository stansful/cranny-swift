// CrannyMedia/Service/MediaService.swift — implements `NowPlayingSource` (`services.nowPlaying`, ARCHITECTURE.md
// §6.5): runs the provider chain with backoff and failover, filters sessions, debounces track changes, decodes
// artwork + palette off the main actor (LRU of 16) and applies commands optimistically, then makes sure a provider
// state confirms them (else it asks once and shows the player's last state again). Event-driven: nothing polls;
// every delay is one sleep on the injected `MediaClock`.
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
    /// Track key of `artwork` (the previous track's art stays up to `artworkGrace` after a change): views use
    /// it as the artwork's identity, so a swap cross-fades exactly when the picture changes.
    private(set) var artworkKey: String?
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
    /// The elected now-playing app as the bridge last reported it, before filters (nil = unknown: not a bridge
    /// provider, or no state yet). 0 = none, which is also what a blocked helper reports (`BridgeHealthMonitor`).
    private(set) var reportedPlayerPID: Int?
    /// Bundle id of `reportedPlayerPID`'s app ("Test media detection" names it even when a filter hides it).
    private(set) var reportedPlayerBundleID: String?

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let clock: any MediaClock
    @ObservationIgnored let visualizer: VisualizerEngine
    /// The blocked-helper heuristic (set by the module; read by diagnostics).
    @ObservationIgnored weak var health: BridgeHealthMonitor?
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
    @ObservationIgnored private let artworkStore = ArtworkStore()
    @ObservationIgnored private var raw: NowPlaying?
    /// Counts provider snapshots: a command is confirmed when this moved on after it was sent.
    @ObservationIgnored private var snapshotSequence = 0
    @ObservationIgnored private var confirmation: Task<Void, Never>?
    /// A seeded sample (Settings stage, onboarding, previews, `--qa-media`): commands change only its own state.
    @ObservationIgnored private var isLocalSession = false
    @ObservationIgnored private var tokens: [ObservationToken] = []

    /// How long the previous artwork stays while the new track's artwork is on its way (60–140 ms, R2 b2).
    static let artworkGrace: Duration = .milliseconds(600)
    /// After an optimistic command: how long to wait for a provider state before asking for one (`refresh`; the
    /// next state normally follows in 60–75 ms, R2) …
    static let confirmationWindow: Duration = .milliseconds(800)
    /// … and how long after that request before the optimistic change is undone (the player's last state).
    static let rollbackWindow: Duration = .milliseconds(700)

    /// `allowsLiveVisualizer`: only the app's real service may run the system audio tap. Samples, previews and QA
    /// services never do: they draw Ambient (or dots) even in Live mode.
    init(settings: SettingsStore, environment: any SystemEnvironment, permissions: PermissionsCenter,
         providers: [MediaProviderFactory], clock: any MediaClock = SystemMediaClock(), allowsLiveVisualizer: Bool = false) {
        self.settings = settings
        self.clock = clock
        self.factories = providers
        visualizer = VisualizerEngine(settings: settings, environment: environment, permissions: permissions, clock: clock,
                                      allowsLive: allowsLiveVisualizer)
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
        confirmation?.cancel(); confirmation = nil
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

    /// Optimistic for play/pause/toggle/seek: the UI changes at once, the provider's next state (60–75 ms later)
    /// is authoritative. A refused command is undone at once; one that no state confirms within
    /// `confirmationWindow` makes the provider re-send its state, and after `rollbackWindow` more the player's last
    /// state is shown again (the bridge de-duplicates states, so an ignored command would otherwise stick).
    /// Nothing changes when the provider can only read. Returns whether the provider accepted the command.
    @discardableResult func send(_ command: MediaCommand) async -> Bool {
        if isLocalSession {
            applyOptimistically(command)              // the sample: nothing to deliver, nothing to confirm
            return false
        }
        guard let provider, supportsCommands else { return false }
        let sequence = snapshotSequence
        let applied = applyOptimistically(command)
        let delivered = await provider.send(command)
        guard applied else { return delivered }
        if delivered {
            awaitConfirmation(since: sequence)
        } else {
            log.info("media: a command was not accepted; showing the player's state again")
            showLastState(ifNothingSince: sequence)
        }
        return delivered
    }

    /// "Test media detection": the helper's round trip, nil = no answer.
    func ping() async -> Duration? { await provider?.ping() }

    /// The kind of the provider in use (nil when none).
    var activeKind: MediaProviderKind? { status.kind }

    /// True when `nowPlaying` changed.
    @discardableResult private func applyOptimistically(_ command: MediaCommand) -> Bool {
        guard var np = nowPlaying else { return false }
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
            return false
        }
        nowPlaying = np
        return true
    }

    private func awaitConfirmation(since sequence: Int) {
        confirmation?.cancel()
        confirmation = Task { [weak self] in
            do { try await self?.clock.sleep(for: Self.confirmationWindow) } catch { return }
            guard !Task.isCancelled, let self, self.snapshotSequence == sequence else { return }   // a state confirmed it
            self.provider?.refresh()
            do { try await self.clock.sleep(for: Self.rollbackWindow) } catch { return }
            guard !Task.isCancelled, self.snapshotSequence == sequence else { return }
            log.info("media: a command was not confirmed; showing the player's state again")
            self.showLastState(ifNothingSince: sequence)
        }
    }

    /// Undoes optimistic changes: the last provider snapshot again, unless a newer one already replaced them.
    private func showLastState(ifNothingSince sequence: Int) {
        guard snapshotSequence == sequence else { return }
        publish(filter.apply(raw))
    }

    // MARK: Provider chain

    private func activate(_ i: Int) {
        generation += 1
        let generation = generation
        pump?.cancel(); pump = nil
        restartTask?.cancel(); restartTask = nil
        confirmation?.cancel(); confirmation = nil
        provider?.stop(); provider = nil
        if reportedPlayerPID != nil { reportedPlayerPID = nil }
        if reportedPlayerBundleID != nil { reportedPlayerBundleID = nil }
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
        case .electedPlayer(let pid, let bundleID):
            if reportedPlayerPID != pid { reportedPlayerPID = pid }
            if reportedPlayerBundleID != bundleID { reportedPlayerBundleID = bundleID }
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
        log.error("media: \(kind.rawValue, privacy: .public) unavailable: \(failure.logName, privacy: .public)")
        if case .launchFailed(let detail) = failure { log.error("media: launch error: \(detail, privacy: .private)") }
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
        snapshotSequence += 1
        raw = incoming
        if let source = incoming?.parentBundleID ?? incoming?.bundleID, recentSources.first != source {
            recentSources = Array(([source] + recentSources.filter { $0 != source }).prefix(8))
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
        if let hit = artworkStore.cached(key) { setArtwork(hit, key: key); return }
        // Keep the previous artwork briefly: the new one usually follows the state within ≈ 100 ms.
        artworkGrace = Task { [weak self] in
            do { try await self?.clock.sleep(for: Self.artworkGrace) } catch { return }
            guard let self, self.nowPlaying?.trackKey == key, self.artworkKey != key else { return }
            self.setArtwork(nil, key: nil)
        }
    }

    /// Late or replaced artwork for the current track is applied (never cleared for the same key: seek glitch);
    /// artwork for another track only fills the cache.
    private func receiveArtwork(key: String, data: Data) {
        artworkStore.receive(key: key, data: data) { [weak self] decoded in
            guard let self, key == self.nowPlaying?.trackKey else { return }
            self.setArtwork(decoded, key: key)
        }
    }

    private func setArtwork(_ decoded: DecodedArtwork?, key: String?) {
        artworkGrace?.cancel(); artworkGrace = nil
        guard artworkKey != key || artwork !== decoded?.image else { return }
        artworkKey = key
        artwork = decoded?.image
        palette = decoded?.palette
    }

    // MARK: Previews, stages and Debug QA

    /// Shows a fixed session without any provider (sample activity, `#Preview`, `--qa-media`).
    func seed(_ np: NowPlaying?, artwork decoded: DecodedArtwork?) {
        if let decoded, let key = np?.trackKey { artworkStore.seed(decoded, for: key) }
        isLocalSession = np != nil
        raw = np
        nowPlaying = np
        lastSourceBundleID = np?.bundleID ?? lastSourceBundleID
        setArtwork(decoded, key: np?.trackKey)
        status = np == nil ? .idle : .running(.sample)
    }
}
