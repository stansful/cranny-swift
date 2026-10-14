// CrannyCore/Services/Ports.swift
// Cross-layer contracts. Implemented by the shell (NotchControl, SystemEnvironment, AppControl) or by a
// feature module (NowPlayingSource ← CrannyMedia, TrayIntake ← CrannyTray). Consumers never import the
// implementing module; they read `registry.services.*`.
import CoreGraphics
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NotchControl (implemented by CrannyAppShell)

/// What happened to the panel, delivered to `NotchControl.addEventObserver(_:)` on the main actor.
public nonisolated enum NotchEvent: Sendable, Equatable {
    /// The Nook opened, and why.
    case opened(OpenReason)
    /// The Nook closed.
    case closed
    /// Pin (⌘P) turned on or off.
    case pinned(Bool)
    /// The open Nook shows another page.
    case pageChanged(PageID)
    /// A drop on the notch was kept (the Tray took `count` files).
    case filesCaught(count: Int)
    /// A two-finger swipe over a compact or peek activity that it did not handle itself.
    case activityGesture(ActivityID, ActivityGesture)
    /// Hold-⌘ hints appeared (onboarding counts it as a completed step).
    case commandHintsShown
    /// The ⌘K palette opened.
    case paletteOpened
}

/// Commands to the notch panel and its events. Implemented by CrannyAppShell; tests use `PreviewNotchControl`.
@MainActor public protocol NotchControl: AnyObject {
    /// Opens on the pointer's display. `focus` scrolls/highlights a widget and gives it keyboard focus.
    func open(page: PageID?, focus: WidgetID?, reason: OpenReason)
    /// Closes the Nook (unless pinned or held open).
    func close()
    /// Pins or unpins the open Nook (⌘P).
    func togglePinned()
    /// Keeps the Nook open while `true` for `reason` (e.g. "notes.editing"). Every `true` needs a `false`.
    func setHoldOpen(_ hold: Bool, reason: String)
    /// Focus mode: the shape resizes to all columns × 3 rows around one widget (Notes). nil ends it.
    func setFocusMode(_ widget: WidgetID?)
    /// Asks for a one-off peek of an activity on the pointer's display (respects pause/full-screen policy).
    func requestPeek(_ activity: ActivityID)
    /// Makes the panel key without activating the app (typing). Released automatically on close.
    func requestKeyboardFocus()
    /// Appearance ▸ Notch fit is being dragged: freeze the real notch in hover and draw the 1-px outline.
    func setCalibrationOverlay(_ visible: Bool)
    /// The current shape in AppKit screen coordinates on the pointer's display (tutorial bubble anchor).
    func shapeFrameOnScreen() -> CGRect?
    /// AirDrop from an on-screen anchor window, re-activating the previous app afterwards (R3 §7).
    func presentAirDrop(_ urls: [URL]) async -> Bool
    /// Share picker (activates Cranny first, R3 §7).
    func presentSharePicker(_ urls: [URL])
    /// Shows a transient P1 compact activity (glyph + short label, 2.6 s) on the pointer display — onboarding
    /// "Hi", "Path copied". Ignored while paused or hidden. `label` is already localized; ≤ 12 characters.
    func flash(symbol: String, label: String)
    /// Calls `handler` for every `NotchEvent`; keep the returned ID to remove it.
    @discardableResult func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID
    /// Stops calling the observer registered under `id`.
    func removeEventObserver(_ id: UUID)
}

// MARK: - SystemEnvironment (implemented by CrannyAppShell)

/// Observable facts about the machine. Read inside SwiftUI bodies or `observe(_:onChange:)`.
@MainActor public protocol SystemEnvironment: AnyObject, Observable {
    /// The session is locked (nothing animates, nothing peeks).
    var isScreenLocked: Bool { get }
    /// Every display is asleep.
    var areDisplaysAsleep: Bool { get }
    /// Low Power Mode is on (effects fall back to the static halo).
    var isLowPowerMode: Bool { get }
    /// The machine's thermal state (serious or critical counts as low power).
    var thermalState: ProcessInfo.ThermalState { get }
    /// Running on battery (effects pace at 20 fps instead of 30).
    var isOnBattery: Bool { get }
    /// The frontmost app (excluded-app checks).
    var frontmostBundleID: String? { get }
    /// A full-screen app (or an excluded app) is in front on the pointer's display.
    var isFullScreenInFront: Bool { get }
    /// General ▸ Demo mode is on: no personal data in screenshots, no sounds.
    var isDemoMode: Bool { get }
    /// The menu bar extra's "Pause Live Activities" is in effect.
    var areLiveActivitiesPaused: Bool { get }
    /// Built-in or Magic Trackpad present (onboarding gesture step, haptics copy).
    var hasTrackpad: Bool { get }
}

public extension SystemEnvironment {
    /// The energy budget for an effect drawn in an open Nook (DESIGN.md §4.7).
    func effectBudget(isOpen: Bool, isOnScreen: Bool, reduceMotion: Bool) -> EffectBudget {
        EffectBudget(isOpen: isOpen, onScreen: isOnScreen && !isScreenLocked && !areDisplaysAsleep,
                     lowPower: isLowPowerMode || thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue,
                     fullScreenFront: isFullScreenInFront, reduceMotion: reduceMotion, onBattery: isOnBattery)
    }
}

// MARK: - AppControl (implemented by CrannyAppShell; used by Settings, Onboarding, menu bar)

/// Whether Cranny opens at login (`SMAppService.mainApp`), or why it cannot say.
public nonisolated enum LoginItemState: Sendable, Equatable { case enabled, disabled, requiresApproval, unavailable(String) }
/// The update check's state, for Settings ▸ About and the menu bar extra.
public nonisolated enum UpdateState: Sendable, Equatable {
    case idle, checking, upToDate
    case available(version: String, notesURL: URL)
    case failed(String)
}
/// A global shortcut is off, registered, or taken by another app.
public nonisolated enum ShortcutState: Sendable, Equatable { case off, registered, conflict }

/// App-level actions for Settings, onboarding and the menu bar extra. Implemented by CrannyAppShell; tests use
/// `PreviewAppControl`.
@MainActor public protocol AppControl: AnyObject, Observable {
    /// Whether Cranny opens at login.
    var loginItem: LoginItemState { get }
    /// Registers or unregisters the login item (General ▸ Open at login).
    func setLaunchAtLogin(_ enabled: Bool)
    /// The last update check's state.
    var update: UpdateState { get }
    /// Checks for an update now ("Check for Updates…").
    func checkForUpdates()
    /// The registration state of a global shortcut.
    func shortcutState(_ id: ShortcutID) -> ShortcutState
    /// Stores the binding (nil = off) and re-registers it; returns the resulting state.
    @discardableResult func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState
    /// Opens Settings, at `page` if given.
    func openSettings(_ page: SettingsPageID?)
    /// Shows the Welcome window.
    func showWelcome()
    /// Starts the interactive tutorial in the real notch.
    func startTutorial()
    /// Plays a preview stage state on the real notch for 5 s ("Show on Notch").
    func showOnNotch(_ state: PreviewStageState)
    /// Resets every setting (content is kept; Settings offers a 10-s Undo).
    func resetAllSettings()
    /// Quits Cranny (the modules' terminate hooks run first).
    func quit()
}

// MARK: - Media (implemented by CrannyMedia)

/// Anchored position: `elapsed` is valid at `timestamp`; interpolate locally, never poll the provider.
public nonisolated struct NowPlaying: Equatable, Sendable {
    /// The player app (nil when unknown, e.g. a web page in a browser without a helper).
    public var bundleID: String?
    /// The hosting app when `bundleID` is a helper process (a browser for a web player).
    public var parentBundleID: String?
    /// The player's display name as the source reports it.
    public var appName: String?
    /// The track title.
    public var title: String
    /// The artist, if any.
    public var artist: String?
    /// The album, if any.
    public var album: String?
    /// The track length in seconds; nil = a live stream.
    public var duration: TimeInterval?
    /// Seconds played at `timestamp`.
    public var elapsed: TimeInterval
    /// When `elapsed` was true.
    public var timestamp: Date
    /// Playback rate (1 = normal speed).
    public var rate: Double
    /// Playing (not paused).
    public var isPlaying: Bool
    /// The source's identifier for the track, if it has one (preferred for `trackKey`).
    public var itemID: String?
    /// The source's identifier for the artwork (artwork cache).
    public var artworkID: String?
    /// Shuffle state, nil when the player does not report it.
    public var shuffle: ShuffleMode?
    /// Repeat state, nil when the player does not report it.
    public var repeatMode: RepeatMode?
    /// The player is Apple Music (its own controls and artwork rules).
    public var isMusicApp: Bool

    /// A snapshot; `elapsed` is valid at `timestamp`.
    public init(bundleID: String?, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsed: TimeInterval = 0, timestamp: Date = Date(),
                rate: Double = 1, isPlaying: Bool, itemID: String? = nil) {
        self.bundleID = bundleID; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.elapsed = elapsed; self.timestamp = timestamp
        self.rate = rate; self.isPlaying = isPlaying; self.itemID = itemID; self.isMusicApp = false
    }
    /// The position at `now`, interpolated from the anchor while playing and clamped to the duration.
    public func position(at now: Date = Date()) -> TimeInterval {
        let speed = rate > 0 ? rate : 1
        let p = isPlaying ? elapsed + now.timeIntervalSince(timestamp) * speed : elapsed
        return max(0, duration.map { min(p, $0) } ?? p)
    }
    /// Identity for "track changed" and the artwork/palette cache.
    public var trackKey: String { itemID ?? [bundleID ?? "", title, artist ?? "", album ?? ""].joined(separator: "|") }
}

/// Shuffle as MediaRemote reports it.
public nonisolated enum ShuffleMode: Int, Codable, Sendable { case off = 1, albums = 2, tracks = 3 }
/// Repeat as MediaRemote reports it.
public nonisolated enum RepeatMode: Int, Codable, Sendable { case off = 1, one = 2, all = 3 }

/// A command to the current player (`NowPlayingSource.send(_:)`).
public nonisolated enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, skipForward15, skipBackward15
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

/// The current track and its controls. Implemented by CrannyMedia (`services.nowPlaying`); read lazily, at use time.
@MainActor public protocol NowPlayingSource: AnyObject, Observable {
    /// The current track, nil when nothing plays or was paused long enough ago.
    var nowPlaying: NowPlaying? { get }
    /// The current artwork, nil until loaded or when there is none.
    var artwork: CGImage? { get }
    /// `AmbientPalette.extract(from:)` of the artwork (cached per track); nil = no artwork yet.
    var palette: AmbientPalette? { get }
    /// Increments on every new track (debounced, playing only, not on the first snapshot after launch).
    var trackChangeCount: Int { get }
    /// 0…1 RMS (60 ms attack / 300 ms release) while the Live visualizer runs; otherwise 0.
    var audioEnergy: Double { get }
    /// Sends a command to the player; true when the player accepted it.
    @discardableResult func send(_ command: MediaCommand) async -> Bool
}

// MARK: - Tray (implemented by CrannyTray)

/// What the shell needs from the Tray: its badge, the drag catch view and the fallback drop.
/// Implemented by CrannyTray (`services.tray`).
@MainActor public protocol TrayIntake: AnyObject, Observable {
    /// Header badge on the Tray page.
    var itemCount: Int { get }
    /// The drag "catch" state (DESIGN.md §8.3): Keep in Tray, AirDrop and up to 3 pinned pipelines that
    /// accept `types`, each declared with `.crannyDropZone`. Shown inside the open shape by CrannyNotchUI.
    func catchView(for types: [UTType]) -> AnyView
    /// Drop that no visible zone took (`NotchZones.performDrop` returned false, e.g. the catch view had not
    /// appeared yet): keep in the tray. The shell calls it; nothing else does.
    func accept(_ payload: DropPayload) async -> Bool
}
