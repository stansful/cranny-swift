// CrannyMirror/Camera/SystemSleepObserver.swift — a second, direct stop signal for the camera (R3 §5: stop on
// `screensDidSleep`, session resign-active and sleep). The model also observes `SystemEnvironment`
// (lock, displays asleep); this covers the moments before the shell's environment catches up, and fast user
// switching, which the environment port does not expose.
import AppKit
import Foundation

final class SystemSleepObserver {
    private var tokens: [any NSObjectProtocol] = []

    /// Calls `onSleep` when the Mac or its displays go to sleep or the user session is switched away.
    func start(_ onSleep: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            // Delivered on the main queue (`queue: .main`), hence `assumeIsolated` (ARCHITECTURE.md §9.1 rule 4).
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onSleep() }
            })
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }
}
