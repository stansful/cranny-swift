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

public nonisolated enum NotchEvent: Sendable, Equatable {
    case opened(OpenReason)
    case closed
    case pinned(Bool)
    case pageChanged(PageID)
    case filesCaught(count: Int)
    case activityGesture(ActivityID, ActivityGesture)
    case commandHintsShown
    case paletteOpened
}

@MainActor public protocol NotchControl: AnyObject {
    /// Opens on the pointer's display. `focus` scrolls/highlights a widget and gives it keyboard focus.
    func open(page: PageID?, focus: WidgetID?, reason: OpenReason)
    func close()
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
    @discardableResult func addEventObserver(_ handler: @escaping @MainActor (NotchEvent) -> Void) -> UUID
    func removeEventObserver(_ id: UUID)
}

// MARK: - SystemEnvironment (implemented by CrannyAppShell)

/// Observable facts about the machine. Read inside SwiftUI bodies or `observe(_:onChange:)`.
@MainActor public protocol SystemEnvironment: AnyObject, Observable {
    var isScreenLocked: Bool { get }
    var areDisplaysAsleep: Bool { get }
    var isLowPowerMode: Bool { get }
    var thermalState: ProcessInfo.ThermalState { get }
    var isOnBattery: Bool { get }
    var frontmostBundleID: String? { get }
    /// A full-screen app (or an excluded app) is in front on the pointer's display.
    var isFullScreenInFront: Bool { get }
    var isDemoMode: Bool { get }
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

public nonisolated enum LoginItemState: Sendable, Equatable { case enabled, disabled, requiresApproval, unavailable(String) }
public nonisolated enum UpdateState: Sendable, Equatable {
    case idle, checking, upToDate
    case available(version: String, notesURL: URL)
    case failed(String)
}
public nonisolated enum ShortcutState: Sendable, Equatable { case off, registered, conflict }

@MainActor public protocol AppControl: AnyObject, Observable {
    var loginItem: LoginItemState { get }
    func setLaunchAtLogin(_ enabled: Bool)
    var update: UpdateState { get }
    func checkForUpdates()
    func shortcutState(_ id: ShortcutID) -> ShortcutState
    /// Stores the binding (nil = off) and re-registers it; returns the resulting state.
    @discardableResult func setShortcut(_ id: ShortcutID, _ combo: KeyCombo?) -> ShortcutState
    func openSettings(_ page: SettingsPageID?)
    func showWelcome()
    func startTutorial()
    /// Plays a preview stage state on the real notch for 5 s ("Show on Notch").
    func showOnNotch(_ state: PreviewStageState)
    func resetAllSettings()
    func quit()
}

// MARK: - Media (implemented by CrannyMedia)

/// Anchored position: `elapsed` is valid at `timestamp`; interpolate locally, never poll the provider.
public nonisolated struct NowPlaying: Equatable, Sendable {
    public var bundleID: String?
    public var parentBundleID: String?
    public var appName: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?        // nil = live stream
    public var elapsed: TimeInterval
    public var timestamp: Date
    public var rate: Double
    public var isPlaying: Bool
    public var itemID: String?
    public var artworkID: String?
    public var shuffle: ShuffleMode?
    public var repeatMode: RepeatMode?
    public var isMusicApp: Bool

    public init(bundleID: String?, title: String, artist: String? = nil, album: String? = nil,
                duration: TimeInterval? = nil, elapsed: TimeInterval = 0, timestamp: Date = Date(),
                rate: Double = 1, isPlaying: Bool, itemID: String? = nil) {
        self.bundleID = bundleID; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.elapsed = elapsed; self.timestamp = timestamp
        self.rate = rate; self.isPlaying = isPlaying; self.itemID = itemID; self.isMusicApp = false
    }
    public func position(at now: Date = Date()) -> TimeInterval {
        let speed = rate > 0 ? rate : 1
        let p = isPlaying ? elapsed + now.timeIntervalSince(timestamp) * speed : elapsed
        return max(0, duration.map { min(p, $0) } ?? p)
    }
    /// Identity for "track changed" and the artwork/palette cache.
    public var trackKey: String { itemID ?? [bundleID ?? "", title, artist ?? "", album ?? ""].joined(separator: "|") }
}

public nonisolated enum ShuffleMode: Int, Codable, Sendable { case off = 1, albums = 2, tracks = 3 }
public nonisolated enum RepeatMode: Int, Codable, Sendable { case off = 1, one = 2, all = 3 }

public nonisolated enum MediaCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, skipForward15, skipBackward15
    case seek(to: TimeInterval)
    case setShuffle(ShuffleMode)
    case setRepeat(RepeatMode)
}

@MainActor public protocol NowPlayingSource: AnyObject, Observable {
    var nowPlaying: NowPlaying? { get }
    var artwork: CGImage? { get }
    /// `AmbientPalette.extract(from:)` of the artwork (cached per track); nil = no artwork yet.
    var palette: AmbientPalette? { get }
    /// Increments on every new track (debounced, playing only, not on the first snapshot after launch).
    var trackChangeCount: Int { get }
    /// 0…1 RMS (60 ms attack / 300 ms release) while the Live visualizer runs; otherwise 0.
    var audioEnergy: Double { get }
    @discardableResult func send(_ command: MediaCommand) async -> Bool
}

// MARK: - Tray (implemented by CrannyTray)

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
