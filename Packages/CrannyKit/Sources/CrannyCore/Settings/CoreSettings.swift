// CrannyCore/Settings/CoreSettings.swift
// Shell-level settings shared by CrannyNotchUI, CrannySettingsUI, CrannyOnboarding and CrannyAppShell.
// Feature modules declare their own keys in their own targets (e.g. TimerSettings).
import Foundation

// MARK: - Value types

/// Settings ▸ General ▸ Open the Nook.
public nonisolated enum OpenMode: String, Codable, CaseIterable, Sendable { case hover, click, shortcutOnly }

/// Settings ▸ General ▸ In full-screen apps (DESIGN.md §3.7).
public nonisolated enum FullScreenPolicy: String, Codable, CaseIterable, Sendable { case hideAll, alertsAndHUD, showAll }

/// Settings ▸ General ▸ Show on.
public nonisolated enum DisplaySelection: Codable, Hashable, Sendable {
    case builtIn            // default when a built-in display is online; falls back to the primary display
    case pointer            // the display with the pointer
    case all
    case custom([DisplayKey])
}

/// Handle on displays without a notch (Appearance).
public nonisolated enum HandleVisibility: String, Codable, CaseIterable, Sendable { case visible, hiddenUntilHover }

/// Per-display row of the General ▸ Show on table, keyed by `DisplayKey`.
public nonisolated struct DisplayPreferences: Codable, Hashable, Sendable {
    /// nil = automatic (hardware notch if present, else `CoreSettings.noNotchStyle`).
    public var style: NoNotchStyle?
    public var showsActivities = true
    public var showsPeeks = true
    public var showsHUD = true
    public init(style: NoNotchStyle? = nil) { self.style = style }
}

/// Appearance ▸ Notch fit, stored per display MODEL ("<vendor>-<model>" from CGDisplayVendorNumber/ModelNumber).
public nonisolated struct NotchFit: Codable, Hashable, Sendable {
    public var widthTune: CGFloat = 0      // −10…+10 pt, 0.5 steps
    public var radiusTune: CGFloat = 0     // −3…+3 pt
    public init(widthTune: CGFloat = 0, radiusTune: CGFloat = 0) { self.widthTune = widthTune; self.radiusTune = radiusTune }
}

/// One card in a Nook page: a widget and its width in cells.
public nonisolated struct NookItem: Codable, Hashable, Sendable {
    public var widget: WidgetID
    public var cells: Int
    public init(_ widget: WidgetID, cells: Int) { self.widget = widget; self.cells = cells }
}

/// A grid page. The built-in grid page has id `.nook`; user pages (≤ 3) get "page.<uuid>".
public nonisolated struct NookPage: Codable, Hashable, Sendable, Identifiable {
    public var id: PageID
    public var title: String?            // nil = built-in localized title ("Home"; code id stays `nook`, D20)
    public var symbol: String
    public var items: [NookItem]
    public init(id: PageID, title: String? = nil, symbol: String, items: [NookItem]) {
        self.id = id; self.title = title; self.symbol = symbol; self.items = items
    }
}

/// Onboarding step 4 presets (DESIGN.md §12.1). Data only, so no layer imports a feature module.
public nonisolated enum NookPreset: String, CaseIterable, Codable, Sendable {
    case listener, maker, meetings, minimal
    public var items: [NookItem] {
        switch self {
        case .listener: [.init(.media, cells: 5), .init(.calendar, cells: 3), .init(.quickApps, cells: 2)]
        case .maker:    [.init(.notes, cells: 4), .init(.todos, cells: 3), .init(.timer, cells: 2), .init(.quickApps, cells: 1)]
        case .meetings: [.init(.calendar, cells: 4), .init(.mirror, cells: 2), .init(.timer, cells: 2), .init(.quickApps, cells: 2)]
        case .minimal:  [.init(.media, cells: 4)]
        }
    }
    public var page: NookPage { NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: items) }
}

/// Per live-activity user preferences (Settings ▸ Live Activities). Missing entry = kind defaults.
public nonisolated struct ActivityPreference: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var peeksOnChange: Bool
    public init(isEnabled: Bool, peeksOnChange: Bool) { self.isEnabled = isEnabled; self.peeksOnChange = peeksOnChange }
}

// MARK: - Keys

public nonisolated enum CoreSettings {
    // General
    public static let openMode = SettingKey<OpenMode>(.general, "openMode", default: .hover)
    public static let hoverDelay = SettingKey<HoverIntent.Delay>(.general, "hoverDelay", default: HoverIntent.defaultDelay)
    public static let holdOptionToPass = SettingKey<Bool>(.general, "holdOptionToPass", default: true)
    public static let closeOnLeave = SettingKey<Bool>(.general, "closeOnLeave", default: true)
    /// Seconds; 0 = off (5–60).
    public static let openInactivityTimeout = SettingKey<Double>(.general, "openInactivityTimeout", default: 0)
    /// No-notch displays: fade the handle out after `handleIdleDelay` s without activity or hover (DESIGN.md §3.5).
    public static let hideHandleWhenIdle = SettingKey<Bool>(.general, "hideHandleWhenIdle", default: false)
    public static let handleIdleDelay = SettingKey<Double>(.general, "handleIdleDelay", default: 10)
    public static let fullScreenPolicy = SettingKey<FullScreenPolicy>(.general, "fullScreenPolicy", default: .alertsAndHUD)
    public static let excludedBundleIDs = SettingKey<[String]>(.general, "excludedBundleIDs", default: [])
    public static let demoMode = SettingKey<Bool>(.general, "demoMode", default: false)
    public static let demoRedactsCalendar = SettingKey<Bool>(.general, "demoRedactsCalendar", default: true)
    public static let showsMenuBarIcon = SettingKey<Bool>(.general, "showsMenuBarIcon", default: true)
    /// System UI sounds: "Pop" on file caught, "Tink" on to-do done (DESIGN.md §14.3). Muted in Demo mode.
    public static let uiSounds = SettingKey<Bool>(.general, "uiSounds", default: false)

    // Displays
    public static let displaySelection = SettingKey<DisplaySelection>(.displays, "selection", default: .builtIn)
    public static let perDisplay = SettingKey<[DisplayKey: DisplayPreferences]>(.displays, "perDisplay", default: [:])

    // Appearance
    public static let accent = SettingKey<AccentSource>(.appearance, "accent", default: .automatic)
    public static let textSize = SettingKey<CrannyTextSize>(.appearance, "textSize", default: .standard)
    public static let motion = SettingKey<MotionPersonality>(.appearance, "motion", default: .standard)
    public static let ambience = SettingKey<AmbienceLevel>(.appearance, "ambience", default: .subtle)
    public static let effect = SettingKey<AmbientEffect>(.appearance, "effect", default: .aurora)
    public static let albumGlow = SettingKey<Bool>(.appearance, "albumGlow", default: true)
    public static let underglow = SettingKey<Bool>(.appearance, "underglow", default: true)       // Vivid only
    public static let progressRim = SettingKey<Bool>(.appearance, "progressRim", default: false)
    public static let translucentBackground = SettingKey<Bool>(.appearance, "translucentBackground", default: false)
    public static let glassIsland = SettingKey<Bool>(.appearance, "glassIsland", default: false)
    public static let buttonShape = SettingKey<ButtonShapeStyle>(.appearance, "buttonShape", default: .capsule)
    public static let widgetStyle = SettingKey<WidgetStyle>(.appearance, "widgetStyle", default: .cards)
    public static let density = SettingKey<NookDensity>(.appearance, "density", default: .standard)
    public static let panelPaddingTune = SettingKey<Double>(.appearance, "panelPaddingTune", default: 0)  // ±4 pt
    /// Appearance ▸ Notch fit, per display model: in the Appearance namespace so "Reset Appearance…" resets it and
    /// "Reset General…" (which resets `.displays`) keeps it (DESIGN.md §11.1).
    public static let notchFit = SettingKey<[String: NotchFit]>(.appearance, "notchFit", default: [:])
    public static let noNotchStyle = SettingKey<NoNotchStyle>(.appearance, "noNotchStyle", default: .floatingIsland)
    public static let handleVisibility = SettingKey<HandleVisibility>(.appearance, "handleVisibility", default: .visible)
    public static let typingEffect = SettingKey<Bool>(.appearance, "typingEffect", default: true)

    // Layout & Widgets (code namespace `nook`)
    public static let pages = SettingKey<[NookPage]>(.nook, "pages", default: [NookPreset.listener.page])
    public static let lastPage = SettingKey<PageID>(.nook, "lastPage", default: .nook)

    // Live Activities
    public static let activityPreferences = SettingKey<[ActivityID: ActivityPreference]>(.activities, "preferences", default: [:])
    /// The user's order (ties within a priority class).
    public static let activityOrder = SettingKey<[ActivityID]>(.activities, "order", default: [])
    public static let peekDuration = SettingKey<Double>(.activities, "peekDuration", default: HoverIntent.peekAutoDismiss)
    public static let quickPeekOnHover = SettingKey<Bool>(.activities, "quickPeekOnHover", default: true)
    public static let satellite = SettingKey<Bool>(.activities, "satellite", default: true)
    /// Seconds; 0 = never. Collapses compact to closed (keeps the satellite).
    public static let compactInactivityTimeout = SettingKey<Double>(.activities, "compactInactivityTimeout", default: 0)
    public static let swipeToDismiss = SettingKey<Bool>(.activities, "swipeToDismiss", default: true)
    public static let autoUnhide = SettingKey<Bool>(.activities, "autoUnhide", default: true)
    public static let menuBarCourtesy = SettingKey<Bool>(.activities, "menuBarCourtesy", default: true)
    /// Menu bar extra ▸ Pause Live Activities. nil = not paused; `.distantFuture` = until resumed.
    public static let pausedUntil = SettingKey<Date?>(.activities, "pausedUntil", default: nil)

    // Gestures
    public static let trackSwipe = SettingKey<Bool>(.gestures, "trackSwipe", default: true)
    public static let invertTrackSwipe = SettingKey<Bool>(.gestures, "invertTrackSwipe", default: false)
    public static let swipeOpenClose = SettingKey<Bool>(.gestures, "swipeOpenClose", default: true)
    public static let gestureSensitivity = SettingKey<Double>(.gestures, "sensitivity", default: 1)   // 0.5…1.5
    public static let haptics = SettingKey<Bool>(.gestures, "haptics", default: true)

    // Keyboard
    /// User overrides; a missing entry means the shortcut's `defaultCombo`; an explicit nil means "off".
    public static let shortcuts = SettingKey<[ShortcutID: KeyCombo?]>(.keyboard, "shortcuts", default: [:])
    /// `CaptureTarget.id` ("notes", "todos") or nil = off.
    public static let typeToCapture = SettingKey<String?>(.keyboard, "typeToCapture", default: "notes")

    // Onboarding & updates
    public static let onboardingCompletedVersion = SettingKey<String?>(.onboarding, "completedVersion", default: nil)
    public static let tutorialCompleted = SettingKey<Bool>(.onboarding, "tutorialCompleted", default: false)
    public static let checksForUpdates = SettingKey<Bool>(.updates, "automatic", default: true)
    public static let includesPrereleases = SettingKey<Bool>(.updates, "prereleases", default: false)
    public static let lastUpdateCheck = SettingKey<Date?>(.updates, "lastCheck", default: nil)
}
