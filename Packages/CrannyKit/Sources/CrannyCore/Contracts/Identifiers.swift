// CrannyCore/Contracts/Identifiers.swift
// Typed string identifiers. Raw values are stable and persisted (settings, layouts): never rename one.
import Foundation

/// A string identifier tagged with a phantom type so a `WidgetID` can never be passed as an `ActivityID`.
/// Encodes as a plain JSON string and can be a JSON dictionary key (`CodingKeyRepresentable`).
public nonisolated struct CrannyID<Tag>: RawRepresentable, Hashable, Sendable, Codable, CodingKeyRepresentable,
                                         ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public nonisolated enum ModuleTag {}
public nonisolated enum WidgetTag {}
public nonisolated enum ActivityTag {}
public nonisolated enum PageTag {}
public nonisolated enum SettingsPageTag {}
public nonisolated enum CommandTag {}
public nonisolated enum ShortcutTag {}
public nonisolated enum DropZoneTag {}
public nonisolated enum ScrollZoneTag {}
public nonisolated enum DisplayTag {}

/// Namespace of a module or of a shell settings group: "timer", "appearance". Prefix of settings keys and log categories.
public typealias ModuleID = CrannyID<ModuleTag>
/// "<module>.<name>", e.g. "media.player".
public typealias WidgetID = CrannyID<WidgetTag>
/// "<module>.<name>", e.g. "timer.running".
public typealias ActivityID = CrannyID<ActivityTag>
/// A page in the Nook header ("nook", "tray", or a user page "page.<uuid>").
public typealias PageID = CrannyID<PageTag>
public typealias SettingsPageID = CrannyID<SettingsPageTag>
public typealias CommandID = CrannyID<CommandTag>
public typealias ShortcutID = CrannyID<ShortcutTag>
public typealias DropZoneID = CrannyID<DropZoneTag>
public typealias ScrollZoneID = CrannyID<ScrollZoneTag>
/// `CGDisplayCreateUUIDFromDisplayID` string: stable across reconnects and reboots (display IDs are not).
public typealias DisplayKey = CrannyID<DisplayTag>

// MARK: - Well-known identifiers (declared here so layers never import each other to name things)
// Static stored properties are not allowed in generic types, hence computed properties.

public extension CrannyID where Tag == ModuleTag {
    static var media: ModuleID { "media" }
    static var calendar: ModuleID { "calendar" }
    static var quickApps: ModuleID { "quickapps" }
    static var mirror: ModuleID { "mirror" }
    static var notes: ModuleID { "notes" }
    static var todos: ModuleID { "todos" }
    static var timer: ModuleID { "timer" }
    static var tray: ModuleID { "tray" }
    static var hud: ModuleID { "hud" }
    static var system: ModuleID { "system" }
    static var effects: ModuleID { "effects" }
    // Shell-owned settings namespaces (CoreSettings)
    static var general: ModuleID { "general" }
    static var appearance: ModuleID { "appearance" }
    static var displays: ModuleID { "displays" }
    static var nook: ModuleID { "nook" }
    static var activities: ModuleID { "activities" }
    static var gestures: ModuleID { "gestures" }
    static var keyboard: ModuleID { "keyboard" }
    static var onboarding: ModuleID { "onboarding" }
    static var updates: ModuleID { "updates" }
    static var shell: ModuleID { "shell" }
}

public extension CrannyID where Tag == WidgetTag {
    static var media: WidgetID { "media.player" }
    static var calendar: WidgetID { "calendar.agenda" }
    static var quickApps: WidgetID { "quickapps.launcher" }
    static var mirror: WidgetID { "mirror.camera" }
    static var notes: WidgetID { "notes.editor" }
    static var todos: WidgetID { "todos.list" }
    static var timer: WidgetID { "timer.clock" }
    static var airDrop: WidgetID { "tray.airdrop" }
    static var files: WidgetID { "tray.shelf" }
}

public extension CrannyID where Tag == ActivityTag {
    static var nowPlaying: ActivityID { "media.nowPlaying" }
    static var meetingSoon: ActivityID { "calendar.meetingSoon" }
    static var meetingNow: ActivityID { "calendar.meetingNow" }
    static var timerRunning: ActivityID { "timer.running" }
    static var timerDone: ActivityID { "timer.done" }
    static var charging: ActivityID { "system.charging" }
    static var lowBattery: ActivityID { "system.lowBattery" }
    static var bluetoothDevice: ActivityID { "system.bluetooth" }
    static var hud: ActivityID { "hud.level" }
    /// Shell-owned transient activity behind `NotchControl.flash(symbol:label:)` (onboarding "Hi", confirmations).
    static var flash: ActivityID { "shell.flash" }
}

public extension CrannyID where Tag == PageTag {
    static var nook: PageID { "nook" }
    static var tray: PageID { "tray" }
}

public extension CrannyID where Tag == DropZoneTag {
    /// Default target of any file drop that does not land on a specific zone.
    static var trayKeep: DropZoneID { "tray.keep" }
    static var airDrop: DropZoneID { "tray.airdrop" }
}

public extension CrannyID where Tag == SettingsPageTag {
    static var general: SettingsPageID { "general" }
    static var appearance: SettingsPageID { "appearance" }
    static var keyboard: SettingsPageID { "keyboard" }
    static var nookAndWidgets: SettingsPageID { "nook" }
    static var liveActivities: SettingsPageID { "activities" }
    static var hud: SettingsPageID { "hud" }
    static var gestures: SettingsPageID { "gestures" }
    static var media: SettingsPageID { "media" }
    static var calendar: SettingsPageID { "calendar" }
    static var shortcuts: SettingsPageID { "shortcuts" }
    static var tray: SettingsPageID { "tray" }
    static var permissions: SettingsPageID { "permissions" }
    static var about: SettingsPageID { "about" }
}

public extension CrannyID where Tag == ShortcutTag {
    static var openNook: ShortcutID { "shell.openNook" }
    static var openTray: ShortcutID { "tray.open" }
    static var newNote: ShortcutID { "notes.new" }
    static var startTimer: ShortcutID { "timer.start" }
    static var togglePin: ShortcutID { "shell.togglePin" }
    static var pauseActivities: ShortcutID { "shell.pauseActivities" }
}

/// Matched-geometry identifiers shared across layers (compact slot → peek row → widget).
public nonisolated enum MatchedID {
    public static let mediaArtwork = "media.artwork"
    public static let timerRing = "timer.ring"
}
