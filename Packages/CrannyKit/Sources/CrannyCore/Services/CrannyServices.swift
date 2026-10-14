// CrannyCore/Services/CrannyServices.swift
// The service hub every module receives through `ModuleRegistry.services`.
import Foundation
import Observation

@MainActor @Observable public final class CrannyServices {
    public let settings: SettingsStore
    public let permissions: PermissionsCenter
    public let haptics: Haptics
    public let paths: AppPaths
    public let notch: any NotchControl
    public let environment: any SystemEnvironment
    public let app: any AppControl
    /// Set by CrannyMedia in `register(in:)`. Read lazily (at use time), never cache in `register`.
    public var nowPlaying: (any NowPlayingSource)?
    /// Set by CrannyTray in `register(in:)`.
    public var tray: (any TrayIntake)?
    /// VoiceOver announcements with the app-wide limit of DESIGN.md §16 (one alert or result per 10 s). Tests replace
    /// it with an `Announcer(post:now:)` that records.
    public var announcer = Announcer()

    public init(settings: SettingsStore, permissions: PermissionsCenter, haptics: Haptics, paths: AppPaths,
                notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl) {
        self.settings = settings; self.permissions = permissions; self.haptics = haptics; self.paths = paths
        self.notch = notch; self.environment = environment; self.app = app
    }

    /// In-memory settings (`InMemoryDefaults`: nothing is written to ~/Library/Preferences), temporary paths and
    /// recording doubles: for `#Preview` and unit tests. Every call returns independent settings.
    public static func preview(environment: PreviewSystemEnvironment = PreviewSystemEnvironment()) -> CrannyServices {
        let settings = SettingsStore(defaults: InMemoryDefaults())
        return CrannyServices(settings: settings, permissions: PermissionsCenter(),
                              haptics: Haptics(isEnabled: { false }), paths: .temporary(),
                              notch: PreviewNotchControl(), environment: environment, app: PreviewAppControl())
    }
}

// MARK: - Test doubles (public: used by every module's tests and #Previews)

@MainActor public final class PreviewNotchControl: NotchControl {
    /// Every call, in order ("open(nook,timer.clock,click)", "close", "hold(true,notes.editing)").
    public private(set) var calls: [String] = []
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]
    public init() {}
    public func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        calls.append("open(\(page?.rawValue ?? "-"),\(focus?.rawValue ?? "-"),\(reason.rawValue))")
    }
    public func close() { calls.append("close") }
    public func togglePinned() { calls.append("togglePinned") }
    public func setHoldOpen(_ hold: Bool, reason: String) { calls.append("hold(\(hold),\(reason))") }
    public func setFocusMode(_ widget: WidgetID?) { calls.append("focus(\(widget?.rawValue ?? "-"))") }
    public func requestPeek(_ activity: ActivityID) { calls.append("peek(\(activity))") }
    public func requestKeyboardFocus() { calls.append("key") }
    public func setCalibrationOverlay(_ visible: Bool) { calls.append("calibration(\(visible))") }
    public func shapeFrameOnScreen() -> CGRect? { nil }
    public func presentAirDrop(_ urls: [URL]) async -> Bool { calls.append("airdrop(\(urls.count))"); return true }
    public func presentSharePicker(_ urls: [URL]) { calls.append("share(\(urls.count))") }
    public func flash(symbol: String, label: String) { calls.append("flash(\(symbol))") }
    public func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    public func removeEventObserver(_ id: UUID) { observers[id] = nil }
    /// Tests: simulate the shell emitting an event.
    public func emit(_ event: NotchEvent) { for o in observers.values { o(event) } }
}

@MainActor @Observable public final class PreviewSystemEnvironment: SystemEnvironment {
    public var isScreenLocked = false
    public var areDisplaysAsleep = false
    public var isLowPowerMode = false
    public var thermalState = ProcessInfo.ThermalState.nominal
    public var isOnBattery = false
    public var frontmostBundleID: String? = nil
    public var isFullScreenInFront = false
    public var isDemoMode = false
    public var areLiveActivitiesPaused = false
    public var hasTrackpad = true
    public init() {}
}

@MainActor @Observable public final class PreviewAppControl: AppControl {
    public var loginItem: LoginItemState = .disabled
    public var update: UpdateState = .idle
    public var shortcuts: [ShortcutID: KeyCombo] = [:]
    public init() {}
    public func setLaunchAtLogin(_ enabled: Bool) { loginItem = enabled ? .enabled : .disabled }
    public func checkForUpdates() { update = .upToDate }
    public func shortcutState(_ id: ShortcutID) -> ShortcutState { shortcuts[id] == nil ? .off : .registered }
    public func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { shortcuts[id] = combo; return shortcutState(id) }
    public func openSettings(_ page: SettingsPageID?) {}
    public func showWelcome() {}
    public func startTutorial() {}
    public func showOnNotch(_ state: PreviewStageState) {}
    public func resetAllSettings() {}
    public func quit() {}
}
