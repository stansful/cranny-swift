// Test doubles for CrannyMedia: a manual clock (deterministic backoff/debounce/timeouts) and a scripted provider
// (never reaches a real player, never spawns a helper).
import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import CrannyMedia

/// Time only moves when a test calls `advance`. Sleepers whose deadline passed are resumed in order.
@MainActor final class ManualClock: MediaClock {
    private(set) var now: Date
    private var sleepers: [(id: UUID, deadline: Date, continuation: CheckedContinuation<Void, any Error>)] = []

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) { self.now = now }

    var pendingSleepers: Int { sleepers.count }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let deadline = now.addingTimeInterval(duration.timeInterval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                sleepers.append((id, deadline, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Moves time forward and lets resumed tasks run.
    func advance(by duration: Duration) async {
        now = now.addingTimeInterval(duration.timeInterval)
        let due = sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
        sleepers.removeAll { s in due.contains { $0.id == s.id } }
        for sleeper in due { sleeper.continuation.resume() }
        await settle()
    }

    private func cancel(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// Lets queued main-actor tasks run (stream pumps, debounce tasks, artwork decoding).
@MainActor func settle(_ rounds: Int = 30) async {
    for _ in 0..<rounds { await Task.yield() }
}

/// Waits in real time until `condition` holds — for work that hops off the main actor (artwork decode). Returns as
/// soon as it holds; the generous bound only decides how long a failing test waits. A short one flakes: while the
/// suite starts, parallel tests can keep the main actor busy for seconds, and this loop runs on it.
@MainActor func eventually(timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// A provider driven by the test: `emit` pushes events, `commands` records what the service sent, `accepts` is
/// what `send` answers (the bridge's `ack ok`), `refreshes` counts state requests.
nonisolated final class ScriptedProvider: MediaProvider, @unchecked Sendable {   // test-only; used on the main actor
    let kind: MediaProviderKind
    let supportsCommands: Bool
    var accepts = true
    private(set) var commands: [MediaCommand] = []
    private(set) var refreshes = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private var continuation: AsyncStream<ProviderEvent>.Continuation?

    init(kind: MediaProviderKind = .perl, supportsCommands: Bool = true) {
        self.kind = kind
        self.supportsCommands = supportsCommands
    }

    func start() -> AsyncStream<ProviderEvent> {
        starts += 1
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self)
        self.continuation = continuation
        return stream
    }
    func send(_ command: MediaCommand) async -> Bool { commands.append(command); return accepts }
    func refresh() { refreshes += 1 }
    func ping() async -> Duration? { .milliseconds(3) }
    func stop() { stops += 1; continuation?.finish(); continuation = nil }

    func emit(_ event: ProviderEvent) {
        continuation?.yield(event)
        if case .unavailable = event { continuation?.finish(); continuation = nil }
    }
    var isStarted: Bool { continuation != nil }
}

@MainActor enum Fixtures {
    static func track(_ title: String, artist: String? = "Artist", bundleID: String = "com.apple.Music", itemID: String? = nil,
                      playing: Bool = true, elapsed: TimeInterval = 10, duration: TimeInterval? = 200,
                      timestamp: Date = Date(timeIntervalSince1970: 1_000_000)) -> NowPlaying {
        NowPlaying(bundleID: bundleID, title: title, artist: artist, duration: duration, elapsed: elapsed,
                   timestamp: timestamp, rate: playing ? 1 : 0, isPlaying: playing, itemID: itemID)
    }

    /// A service with the given scripted providers and a manual clock, on throw-away settings.
    static func service(_ providers: [ScriptedProvider?], clock: ManualClock, services: CrannyServices = .preview()) -> MediaService {
        MediaService(settings: services.settings, environment: services.environment, permissions: services.permissions,
                     providers: providers.enumerated().map { _, provider in
                         MediaProviderFactory(kind: provider?.kind ?? .perl) { provider }
                     }, clock: clock)
    }

    /// PNG bytes of a solid-colour image.
    static func png(red: CGFloat, green: CGFloat, blue: CGFloat, side: Int = 32) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = ctx.makeImage() else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
