// CrannyCore/Services/CrannyServices.swift
// The service hub every module receives through `ModuleRegistry.services`.
import Foundation
import Observation

/// Everything a module may use besides its own code, created once by the shell and handed to every module as
/// `registry.services`. Tests and previews use `CrannyServices.preview()`.
@MainActor @Observable public final class CrannyServices {
    /// Typed, observable settings (each module's keys and `CoreSettings`).
    public let settings: SettingsStore
    /// The only place that queries or requests TCC permissions.
    public let permissions: PermissionsCenter
    /// Trackpad haptics, already gated by Gestures ▸ Haptic feedback.
    public let haptics: Haptics
    /// Where modules keep files (`directory(for:)`, `cacheDirectory(for:)`).
    public let paths: AppPaths
    /// Commands to the panel and its events (implemented by the shell).
    public let notch: any NotchControl
    /// Observable machine state: lock, sleep, power, full screen, Demo mode.
    public let environment: any SystemEnvironment
    /// App-level actions: login item, updates, shortcuts, Settings and onboarding windows.
    public let app: any AppControl
    /// Set by CrannyMedia in `register(in:)`. Read lazily (at use time), never cache in `register`.
    public var nowPlaying: (any NowPlayingSource)?
    /// Set by CrannyTray in `register(in:)`.
    public var tray: (any TrayIntake)?
    /// VoiceOver announcements with the app-wide limit of DESIGN.md §16 (one alert or result per 10 s). Tests replace
    /// it with an `Announcer(post:now:)` that records.
    public var announcer = Announcer()

    /// The hub; the composition root builds the real one.
    public init(settings: SettingsStore, permissions: PermissionsCenter, haptics: Haptics, paths: AppPaths,
                notch: any NotchControl, environment: any SystemEnvironment, app: any AppControl) {
        self.settings = settings; self.permissions = permissions; self.haptics = haptics; self.paths = paths
        self.notch = notch; self.environment = environment; self.app = app
    }

    /// In-memory settings (`InMemoryDefaults`: nothing is written to ~/Library/Preferences), permissions that never
    /// ask macOS (`PermissionsCenter.preview()`), temporary paths and recording doubles: for `#Preview` and unit
    /// tests. Every call returns independent settings.
    public static func preview(environment: PreviewSystemEnvironment = PreviewSystemEnvironment()) -> CrannyServices {
        let settings = SettingsStore(defaults: InMemoryDefaults())
        return CrannyServices(settings: settings, permissions: .preview(),
                              haptics: Haptics(isEnabled: { false }), paths: .temporary(),
                              notch: PreviewNotchControl(), environment: environment, app: PreviewAppControl())
    }
}

// MARK: - Test doubles (public: used by every module's tests and #Previews)

/// A `NotchControl` that records calls and lets tests emit events (`calls`, `emit(_:)`).
@MainActor public final class PreviewNotchControl: NotchControl {
    /// Every call, in order ("open(nook,timer.clock,click)", "close", "hold(true,notes.editing)").
    public private(set) var calls: [String] = []
    private var observers: [UUID: @MainActor (NotchEvent) -> Void] = [:]
    /// A double with no calls recorded.
    public init() {}
    /// Records "open(<page>,<widget>,<reason>)".
    public func open(page: PageID?, focus: WidgetID?, reason: OpenReason) {
        calls.append("open(\(page?.rawValue ?? "-"),\(focus?.rawValue ?? "-"),\(reason.rawValue))")
    }
    /// Records "close".
    public func close() { calls.append("close") }
    /// Records "togglePinned".
    public func togglePinned() { calls.append("togglePinned") }
    /// Records "hold(<hold>,<reason>)".
    public func setHoldOpen(_ hold: Bool, reason: String) { calls.append("hold(\(hold),\(reason))") }
    /// Records "focus(<widget>)".
    public func setFocusMode(_ widget: WidgetID?) { calls.append("focus(\(widget?.rawValue ?? "-"))") }
    /// Records "peek(<activity>)".
    public func requestPeek(_ activity: ActivityID) { calls.append("peek(\(activity))") }
    /// Records "key".
    public func requestKeyboardFocus() { calls.append("key") }
    /// Records "calibration(<visible>)".
    public func setCalibrationOverlay(_ visible: Bool) { calls.append("calibration(\(visible))") }
    /// No panel: nil.
    public func shapeFrameOnScreen() -> CGRect? { nil }
    /// Records "airdrop(<count>)" and reports success.
    public func presentAirDrop(_ urls: [URL]) async -> Bool { calls.append("airdrop(\(urls.count))"); return true }
    /// Records "share(<count>)".
    public func presentSharePicker(_ urls: [URL]) { calls.append("share(\(urls.count))") }
    /// Records "flash(<symbol>)".
    public func flash(symbol: String, label: String) { calls.append("flash(\(symbol))") }
    /// Registers `handler` for `emit(_:)`.
    public func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID {
        let id = UUID(); observers[id] = handler; return id
    }
    /// Unregisters an observer.
    public func removeEventObserver(_ id: UUID) { observers[id] = nil }
    /// Tests: simulate the shell emitting an event.
    public func emit(_ event: NotchEvent) { for o in observers.values { o(event) } }
}

/// A `SystemEnvironment` whose facts tests set directly (all quiet and on AC power by default).
@MainActor @Observable public final class PreviewSystemEnvironment: SystemEnvironment {
    /// See `SystemEnvironment.isScreenLocked`.
    public var isScreenLocked = false
    /// See `SystemEnvironment.areDisplaysAsleep`.
    public var areDisplaysAsleep = false
    /// See `SystemEnvironment.isLowPowerMode`.
    public var isLowPowerMode = false
    /// See `SystemEnvironment.thermalState`.
    public var thermalState = ProcessInfo.ThermalState.nominal
    /// See `SystemEnvironment.isOnBattery`.
    public var isOnBattery = false
    /// See `SystemEnvironment.frontmostBundleID`.
    public var frontmostBundleID: String? = nil
    /// See `SystemEnvironment.isFullScreenInFront`.
    public var isFullScreenInFront = false
    /// See `SystemEnvironment.isDemoMode`.
    public var isDemoMode = false
    /// See `SystemEnvironment.areLiveActivitiesPaused`.
    public var areLiveActivitiesPaused = false
    /// See `SystemEnvironment.hasTrackpad`.
    public var hasTrackpad = true
    public var canPresentHUD = true
    public init() {}
}

/// An `AppControl` that keeps its state in memory (login item, update state, shortcut bindings).
@MainActor @Observable public final class PreviewAppControl: AppControl {
    /// See `AppControl.loginItem`.
    public var loginItem: LoginItemState = .disabled
    /// See `AppControl.update`.
    public var update: UpdateState = .idle
    /// The bindings `setShortcut(_:_:)` stored.
    public var shortcuts: [ShortcutID: KeyCombo] = [:]
    /// No login item, no update, no bindings.
    public init() {}
    /// Sets `loginItem` to enabled or disabled.
    public func setLaunchAtLogin(_ enabled: Bool) { loginItem = enabled ? .enabled : .disabled }
    /// Sets `update` to up to date.
    public func checkForUpdates() { update = .upToDate }
    /// Registered when a binding is stored, else off.
    public func shortcutState(_ id: ShortcutID) -> ShortcutState { shortcuts[id] == nil ? .off : .registered }
    /// Stores the binding.
    public func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState { shortcuts[id] = combo; return shortcutState(id) }
    /// Does nothing.
    public func openSettings(_ page: SettingsPageID?) {}
    /// Does nothing.
    public func showWelcome() {}
    /// Does nothing.
    public func startTutorial() {}
    /// Does nothing.
    public func showOnNotch(_ state: PreviewStageState) {}
    /// Does nothing.
    public func resetAllSettings() {}
    /// Does nothing.
    public func quit() {}
}
