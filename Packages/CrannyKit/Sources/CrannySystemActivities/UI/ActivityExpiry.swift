// CrannySystemActivities/UI/ActivityExpiry.swift — ends a transient activity: one sleep to its deadline,
// no polling (ARCHITECTURE.md §9.1 rule 7, §9.2). The activity also publishes the deadline as `expiresAt`.
import Foundation

@MainActor final class ActivityExpiry {
    private var task: Task<Void, Never>?

    /// Replaces any pending deadline.
    func schedule(after seconds: TimeInterval, _ end: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(max(seconds, 0)))
            guard !Task.isCancelled else { return }
            end()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
