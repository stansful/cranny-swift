// CrannyQuickApps/Apps/RunningAppsObserver.swift — the Dock-style running dots (DESIGN.md §7.3), event-driven.
//
// One snapshot of `runningApplications` at start, then `didLaunch`/`didTerminateApplication` notifications from
// NSWorkspace's notification centre (delivered on the main queue). No polling, no timers (ARCHITECTURE.md §9.2).
import AppKit
import Foundation
import Observation

@MainActor @Observable final class RunningAppsObserver {
    private(set) var running = RunningApps()
    /// Bundle id of the last app that launched (the model re-resolves quick apps it could not find).
    @ObservationIgnored var onLaunch: (@MainActor (String) -> Void)?

    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private let snapshot: @MainActor () -> [String]
    @ObservationIgnored private var tokens: [any NSObjectProtocol] = []

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         snapshot: @escaping @MainActor () -> [String] = { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) }) {
        self.center = center; self.snapshot = snapshot
    }

    func isRunning(_ bundleID: String) -> Bool { running.contains(bundleID) }

    func start() {
        guard tokens.isEmpty else { return }
        running = RunningApps(snapshot())
        tokens = [
            observe(NSWorkspace.didLaunchApplicationNotification) { observer, id in
                observer.running.launched(id)
                observer.onLaunch?(id)
            },
            observe(NSWorkspace.didTerminateApplicationNotification) { observer, id in observer.running.terminated(id) },
        ]
    }

    func stop() {
        for token in tokens { center.removeObserver(token) }
        tokens = []
    }

    private func observe(_ name: Notification.Name,
                         _ apply: @escaping @MainActor (RunningAppsObserver, String) -> Void) -> any NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let id = app?.bundleIdentifier else { return }
            // Delivered on the main queue (`queue: .main` above).
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(self, id)
            }
        }
    }
}
