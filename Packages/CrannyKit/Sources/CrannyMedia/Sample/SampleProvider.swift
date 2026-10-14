// CrannyMedia/Sample/SampleProvider.swift — a provider with a fixed snapshot for Debug visual QA (`--qa-media none`)
// and previews of the provider states. Commands are accepted and dropped: nothing reaches a real player.
import CrannyCore
import Foundation
import os

nonisolated final class SampleProvider: MediaProvider, @unchecked Sendable {   // the continuation is behind `lock`
    let kind = MediaProviderKind.sample
    let supportsCommands = true
    private let snapshot: NowPlaying?
    private let lock = OSAllocatedUnfairLock<AsyncStream<ProviderEvent>.Continuation?>(initialState: nil)

    init(snapshot: NowPlaying?) { self.snapshot = snapshot }

    func start() -> AsyncStream<ProviderEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ProviderEvent.self)
        lock.withLock { $0 = continuation }
        continuation.yield(.nowPlaying(snapshot))
        return stream
    }

    func send(_ command: MediaCommand) async -> Bool { true }
    func ping() async -> Duration? { .zero }
    func stop() { lock.withLock { $0?.finish(); $0 = nil } }
}
