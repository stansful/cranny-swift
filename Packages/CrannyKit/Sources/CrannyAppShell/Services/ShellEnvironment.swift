// CrannyAppShell/Services/ShellEnvironment.swift — the `SystemEnvironment` port (ARCHITECTURE.md §7.10).
// Event-driven only: lock/unlock and fast user switching, display sleep, Low Power Mode, thermal state, AC vs battery
// (IOKit's limited-power notification: it fires only when the providing source switches between AC, battery and UPS,
// never on the battery's percent or time-remaining updates), frontmost app, Reduce Motion, trackpad presence, and
// per-display full-screen detection (§5.7) re-evaluated 0.6 s after Space/app/screen changes (and on demand right
// before a hover-open). Demo mode and "Pause Live Activities" are derived from CoreSettings by observation; their only
// writers are DemoMode and PauseController.
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
    private(set) var isDemoMode = false
    private(set) var areLiveActivitiesPaused = false
    private(set) var hasTrackpad = TrackpadDetector.isTrackpadPresent()
    /// System ▸ Accessibility ▸ Reduce motion (delight caps, §4.6 step 7).
    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// What is in front of each display (§5.7); missing = nothing full screen.
    private(set) var fronts: [CGDirectDisplayID: FullScreenDetector.Front] = [:]
    /// The display under the pointer (the coordinator updates it when the pointer crosses displays).
    private(set) var pointerDisplay: CGDirectDisplayID?
    /// A HUD shown now would be drawn (`SystemEnvironment.canPresentHUD`); the coordinator decides it with every
    /// display-facts update (`OverlayCoordinator.canPresentHUD()`).
    private(set) var canPresentHUD = true

    /// A full-screen app (or an excluded app) is in front on the pointer's display.
    var isFullScreenInFront: Bool {
        guard let front = pointerDisplay.flatMap({ fronts[$0] }) else { return false }
        return front.fullScreen || front.excludedApp
    }

    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private var settingsTokens: [ObservationToken] = []
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private let fullScreenDebouncer = Debouncer(delay: .milliseconds(600))
    @ObservationIgnored private let trackpads = TrackpadDetector()
    @ObservationIgnored private var excludedBundleIDs: Set<String> = []
    @ObservationIgnored private var locked = false
    @ObservationIgnored private var sessionActive = true
    /// The Dock, whose windows never count as full screen. Kept between checks (it changes only when the Dock
    /// restarts), so a check does not search the running applications each time.
    @ObservationIgnored private var dock: NSRunningApplication?
    /// Target of the IOKit power-source callback (a C function pointer cannot capture context).
    private static weak var current: ShellEnvironment?

    init() {}

    /// Starts observing. Call once, after the registry (and its `SettingsStore`) exists.
    func start(settings: SettingsStore) {
        Self.current = self
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        updateLock()
        refreshPowerSource()

        let distributed = DistributedNotificationCenter.default()
        listen(distributed, "com.apple.screenIsLocked") { $0.locked = true; $0.updateLock() }
        listen(distributed, "com.apple.screenIsUnlocked") { $0.locked = false; $0.updateLock() }
        let workspace = NSWorkspace.shared.notificationCenter
        listen(workspace, NSWorkspace.sessionDidResignActiveNotification.rawValue) { $0.sessionActive = false; $0.updateLock() }
        listen(workspace, NSWorkspace.sessionDidBecomeActiveNotification.rawValue) { $0.sessionActive = true; $0.updateLock() }
        listen(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.areDisplaysAsleep = true }
        listen(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.areDisplaysAsleep = false; $0.scheduleFullScreenCheck() }
        listen(workspace, NSWorkspace.didActivateApplicationNotification.rawValue) {
            $0.frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            $0.scheduleFullScreenCheck()
        }
        listen(workspace, NSWorkspace.activeSpaceDidChangeNotification.rawValue) { $0.scheduleFullScreenCheck() }
        listen(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification.rawValue) {
            $0.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        listen(.default, NSApplication.didChangeScreenParametersNotification.rawValue) { $0.scheduleFullScreenCheck() }
        listen(.default, Notification.Name.NSProcessInfoPowerStateDidChange.rawValue) {
            $0.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        listen(.default, ProcessInfo.thermalStateDidChangeNotification.rawValue) {
            $0.thermalState = ProcessInfo.processInfo.thermalState
        }
        // AC vs battery only (`kIOPSNotifyPowerSource`), not every capacity update of the any-source notification.
        if let source = IOPSCreateLimitedPowerNotification(Self.powerSourceChanged, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        trackpads.start { [weak self] present in self?.hasTrackpad = present }

        settingsTokens.append(observe({ settings[CoreSettings.demoMode] }) { [weak self] in self?.isDemoMode = $0 })
        settingsTokens.append(observe({ settings[CoreSettings.pausedUntil] }) { [weak self] in self?.updatePause($0) })
        settingsTokens.append(observe({ settings[CoreSettings.excludedBundleIDs] }) { [weak self] ids in
            self?.excludedBundleIDs = Set(ids)
            self?.refreshFullScreen()
        })
        isDemoMode = settings[CoreSettings.demoMode]
        excludedBundleIDs = Set(settings[CoreSettings.excludedBundleIDs])
        updatePause(settings[CoreSettings.pausedUntil])
        refreshFullScreen()
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        settingsTokens.removeAll()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        resumeTask?.cancel()
        fullScreenDebouncer.cancel()
        trackpads.stop()
    }

    /// The coordinator tracks the pointer's display (`isFullScreenInFront` is about that one).
    func setPointerDisplay(_ id: CGDirectDisplayID?) {
        if pointerDisplay != id { pointerDisplay = id }
    }

    /// The coordinator's answer to "would a HUD be drawn now?" (the HUD passes its keys to macOS while it is false).
    func setCanPresentHUD(_ value: Bool) {
        if canPresentHUD != value { canPresentHUD = value }
    }

    /// Re-reads the window list now (§5.7 "lazily right before a hover-open or auto-peek").
    func refreshFullScreen() {
        let screens = NSScreen.screens
        let displays = screens.compactMap { screen -> FullScreenDetector.Display? in
            guard let id = DisplayCatalog.displayID(of: screen) else { return nil }
            return FullScreenDetector.Display(id: id, bounds: CGDisplayBounds(id), notchBand: screen.safeAreaInsets.top)
        }
        let front = NSWorkspace.shared.frontmostApplication
        let ignored = Set([ProcessInfo.processInfo.processIdentifier] + [dockPID()].compactMap { $0 })
        let next = FullScreenDetector.evaluate(
            windows: FullScreenDetector.snapshot(), displays: displays, frontmostPID: front?.processIdentifier,
            frontmostIsExcluded: front?.bundleIdentifier.map(excludedBundleIDs.contains) ?? false, ignoredPIDs: ignored)
            .filter { $0.value != FullScreenDetector.Front() }
        if fronts != next { fronts = next }
    }

    /// What is in front of one display (`.alertsAndHUD` / `.hideAll` policy per display, §4.8).
    func front(of display: CGDirectDisplayID) -> FullScreenDetector.Front { fronts[display] ?? FullScreenDetector.Front() }

    // MARK: Private

    private func listen(_ center: NotificationCenter, _ name: String, _ update: @escaping @MainActor (ShellEnvironment) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { update(self) } }          // queue: .main
        }
        observers.append((center, token))
    }

    private func updateLock() {
        let value = locked || !sessionActive
        if isScreenLocked != value { isScreenLocked = value }
    }

    /// The Space animation settles first (R3 §10: re-evaluate ≈ 0.6 s after the notification).
    private func scheduleFullScreenCheck() {
        fullScreenDebouncer.schedule { [weak self] in self?.refreshFullScreen() }
    }

    /// The Dock's process, looked up again only after it quit (the Dock restarts under a new PID) or while none runs.
    private func dockPID() -> pid_t? {
        if let dock, !dock.isTerminated { return dock.processIdentifier }
        dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        return dock?.processIdentifier
    }

    /// The IOKit callback, nonisolated (a closure literal written in a main-actor method would be inferred `@MainActor`).
    private nonisolated static let powerSourceChanged: IOPowerSourceCallbackType = { _ in
        // Delivered on the main run loop (the source is added there).
        MainActor.assumeIsolated { ShellEnvironment.current?.refreshPowerSource() }
    }

    /// UPS power is not battery (it keeps its meaning: only `kIOPMBatteryPowerKey` is).
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
