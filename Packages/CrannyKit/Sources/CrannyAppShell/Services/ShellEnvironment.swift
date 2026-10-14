// CrannyAppShell/Services/ShellEnvironment.swift — the `SystemEnvironment` port (ARCHITECTURE.md §7.10), WP13.
// Event-driven only: lock/unlock, display sleep, Low Power Mode, thermal state, AC vs battery, frontmost
// app; Demo mode and "Pause Live Activities" are derived from CoreSettings by observation (their only
// writers are WP16's DemoMode/PauseController). WP13 adds full-screen detection (§5.7) and trackpad presence.
import AppKit
import CoreGraphics
import CrannyCore
import Foundation
import IOKit.ps
import Observation

@MainActor @Observable final class ShellEnvironment: SystemEnvironment {
    private(set) var isScreenLocked = false
    private(set) var areDisplaysAsleep = false
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var isOnBattery = false
    private(set) var frontmostBundleID: String?
    /// WP13: CGWindowList heuristic of §5.7, re-evaluated 0.6 s after space changes.
    private(set) var isFullScreenInFront = false
    private(set) var isDemoMode = false
    private(set) var areLiveActivitiesPaused = false
    /// WP13: IOKit HID (built-in or Magic Trackpad).
    private(set) var hasTrackpad = true

    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private var settingsTokens: [ObservationToken] = []
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    /// Target of the IOKit power-source callback (a C function pointer cannot capture context).
    private static weak var current: ShellEnvironment?

    init() {}

    /// Starts observing. Call once, after the registry (and its `SettingsStore`) exists.
    func start(settings: SettingsStore) {
        Self.current = self
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        isScreenLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        refreshPowerSource()

        let distributed = DistributedNotificationCenter.default()
        listen(distributed, "com.apple.screenIsLocked") { $0.isScreenLocked = true }
        listen(distributed, "com.apple.screenIsUnlocked") { $0.isScreenLocked = false }
        let workspace = NSWorkspace.shared.notificationCenter
        listen(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.areDisplaysAsleep = true }
        listen(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.areDisplaysAsleep = false }
        listen(workspace, NSWorkspace.didActivateApplicationNotification.rawValue) {
            $0.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        listen(.default, Notification.Name.NSProcessInfoPowerStateDidChange.rawValue) {
            $0.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        listen(.default, ProcessInfo.thermalStateDidChangeNotification.rawValue) {
            $0.thermalState = ProcessInfo.processInfo.thermalState
        }
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            // Delivered on the main run loop (the source is added there).
            MainActor.assumeIsolated { ShellEnvironment.current?.refreshPowerSource() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        settingsTokens.append(observe({ settings[CoreSettings.demoMode] }) { [weak self] in self?.isDemoMode = $0 })
        settingsTokens.append(observe({ settings[CoreSettings.pausedUntil] }) { [weak self] in self?.updatePause($0) })
        isDemoMode = settings[CoreSettings.demoMode]
        updatePause(settings[CoreSettings.pausedUntil])
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        settingsTokens.removeAll()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        resumeTask?.cancel()
    }

    // MARK: Private

    private func listen(_ center: NotificationCenter, _ name: String, _ update: @escaping @MainActor (ShellEnvironment) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { update(self) } }          // queue: .main
        }
        observers.append((center, token))
    }

    private func refreshPowerSource() {
        let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() as String?
        isOnBattery = type == kIOPMBatteryPowerKey
    }

    /// Paused until a date: one sleep to that date, no polling.
    private func updatePause(_ until: Date?) {
        resumeTask?.cancel()
        guard let until, until > Date() else { areLiveActivitiesPaused = false; return }
        areLiveActivitiesPaused = true
        guard until != .distantFuture else { return }
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.areLiveActivitiesPaused = false
        }
    }
}
