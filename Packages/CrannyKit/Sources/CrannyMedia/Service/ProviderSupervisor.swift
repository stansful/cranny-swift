// CrannyMedia/Service/ProviderSupervisor.swift — the restart / failover policy of ARCHITECTURE.md §6.5, as a
// pure value (unit-tested with explicit dates): restart the same provider after 0.5 s, 2 s, 8 s; three
// failures within 60 s → the next provider.
import Foundation

nonisolated struct ProviderSupervisor: Equatable, Sendable {
    nonisolated enum Decision: Equatable, Sendable {
        /// Restart the same provider after this delay.
        case restart(after: Duration)
        /// Give up on this provider and start the next one.
        case failover
    }

    static let backoff: [Duration] = [.milliseconds(500), .seconds(2), .seconds(8)]
    static let window: TimeInterval = 60
    static let failuresBeforeFailover = 3

    /// Failures of the current provider, oldest first.
    private(set) var failures: [Date] = []

    /// Records a failure at `now` and decides. The backoff step counts every failure since the provider was
    /// last healthy for a whole window, so 8 s is reached when failures are spread out (e.g. 40 s apart).
    mutating func recordFailure(at now: Date) -> Decision {
        if let last = failures.last, now.timeIntervalSince(last) >= Self.window { failures.removeAll() }
        failures.append(now)
        let recent = failures.filter { now.timeIntervalSince($0) < Self.window }
        if recent.count >= Self.failuresBeforeFailover {
            failures.removeAll()
            return .failover
        }
        return .restart(after: Self.backoff[min(failures.count, Self.backoff.count) - 1])
    }

    /// A new provider starts with a clean record.
    mutating func reset() { failures.removeAll() }
}
