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
    /// Live activities appear on this display.
    public var showsActivities = true
    /// Peeks appear on this display.
    public var showsPeeks = true
    /// The HUD appears on this display.
    public var showsHUD = true
    /// Preferences with everything shown; `style` nil = automatic.
    public init(style: NoNotchStyle? = nil) { self.style = style }

    /// Whether Cranny appears on a display, decided in one place so the shell's panels (`OverlayCoordinator.panelScreens`)
    /// and the Settings preview stage cannot disagree (ARCHITECTURE §4.9; DESIGN.md §3.7, §11.2). An explicit
    /// per-display Off (General ▸ Displays) hides it on any display. Otherwise Appearance ▸ "On displays without a
    /// notch" (`CoreSettings.noNotchStyle`) applies only where there is no hardware notch: a notched display keeps
    /// Cranny when that style is Off.
    ///
    /// - Parameters:
    ///   - preferences: the display's entry in `CoreSettings.perDisplay` (nil = all defaults, style Automatic).
    ///   - noNotchStyle: `CoreSettings.noNotchStyle`.
    ///   - hasNotch: the display has a camera housing (`NSScreen.safeAreaInsets.top > 0`).
    public static func showsCranny(_ preferences: DisplayPreferences?, noNotchStyle: NoNotchStyle, hasNotch: Bool) -> Bool {
        if let style = preferences?.style { return style != .off }
        return hasNotch || noNotchStyle != .off
    }
}

/// Appearance ▸ Notch fit, stored per display MODEL ("<vendor>-<model>" from CGDisplayVendorNumber/ModelNumber).
public nonisolated struct NotchFit: Codable, Hashable, Sendable {
    /// Width correction, −10…+10 pt in 0.5-pt steps.
    public var widthTune: CGFloat = 0
    /// Corner-radius correction, −3…+3 pt.
    public var radiusTune: CGFloat = 0
    /// A fit; no correction by default.
    public init(widthTune: CGFloat = 0, radiusTune: CGFloat = 0) { self.widthTune = widthTune; self.radiusTune = radiusTune }
}

/// One card in a Nook page: a widget and its width in cells.
public nonisolated struct NookItem: Codable, Hashable, Sendable {
    /// The widget shown.
    public var widget: WidgetID
    /// Its width in cells (clamped to the widget's sizes when drawn).
    public var cells: Int
    /// An item.
    public init(_ widget: WidgetID, cells: Int) { self.widget = widget; self.cells = cells }
}

/// A grid page. The built-in grid page has id `.nook`; user pages (≤ 3) get "page.<uuid>".
public nonisolated struct NookPage: Codable, Hashable, Sendable, Identifiable {
    /// The page's identifier (`.nook` or "page.<uuid>").
    public var id: PageID
    /// The user's title; nil = the built-in localized title ("Home"; the code id stays `nook`, D20).
    public var title: String?
    /// The tab glyph.
    public var symbol: String
    /// The cards, in order.
    public var items: [NookItem]
    /// A page.
    public init(id: PageID, title: String? = nil, symbol: String, items: [NookItem]) {
        self.id = id; self.title = title; self.symbol = symbol; self.items = items
    }
}

/// Onboarding step 4 presets (DESIGN.md §12.1). Data only, so no layer imports a feature module.
public nonisolated enum NookPreset: String, CaseIterable, Codable, Sendable {
    case listener, maker, meetings, minimal
    /// The preset's cards.
    public var items: [NookItem] {
        switch self {
        case .listener: [.init(.media, cells: 5), .init(.calendar, cells: 3), .init(.quickApps, cells: 2)]
        case .maker:    [.init(.notes, cells: 4), .init(.todos, cells: 3), .init(.timer, cells: 2), .init(.quickApps, cells: 1)]
        case .meetings: [.init(.calendar, cells: 4), .init(.mirror, cells: 2), .init(.timer, cells: 2), .init(.quickApps, cells: 2)]
        case .minimal:  [.init(.media, cells: 4)]
        }
    }
    /// The Home page with the preset's cards.
    public var page: NookPage { NookPage(id: .nook, symbol: "square.grid.2x2.fill", items: items) }
}

/// Per live-activity user preferences (Settings ▸ Live Activities). Missing entry = kind defaults.
public nonisolated struct ActivityPreference: Codable, Hashable, Sendable {
    /// The activity shows at all.
    public var isEnabled: Bool
    /// It peeks when it changes meaningfully.
    public var peeksOnChange: Bool
    /// A preference.
    public init(isEnabled: Bool, peeksOnChange: Bool) { self.isEnabled = isEnabled; self.peeksOnChange = peeksOnChange }
}

// MARK: - Keys

/// The shell-level settings keys (DESIGN.md §11). Never rename a key; add a new one and migrate.
public nonisolated enum CoreSettings {
    // General
    /// General ▸ Open the Nook: on hover, on click, or by shortcut only.
    public static let openMode = SettingKey<OpenMode>(.general, "openMode", default: .hover)
    /// General ▸ Hover delay.
    public static let hoverDelay = SettingKey<HoverIntent.Delay>(.general, "hoverDelay", default: HoverIntent.defaultDelay)
    /// General ▸ Hold ⌥ to pass the pointer through without opening.
    public static let holdOptionToPass = SettingKey<Bool>(.general, "holdOptionToPass", default: true)
    /// General ▸ Close when the pointer leaves.
    public static let closeOnLeave = SettingKey<Bool>(.general, "closeOnLeave", default: true)
    /// Seconds; 0 = off (5–60).
    public static let openInactivityTimeout = SettingKey<Double>(.general, "openInactivityTimeout", default: 0)
    /// No-notch displays: fade the handle out after `handleIdleDelay` s without activity or hover (DESIGN.md §3.5).
    public static let hideHandleWhenIdle = SettingKey<Bool>(.general, "hideHandleWhenIdle", default: false)
    /// Seconds of inactivity before the idle handle fades (`hideHandleWhenIdle`).
    public static let handleIdleDelay = SettingKey<Double>(.general, "handleIdleDelay", default: 10)
    /// General ▸ In full-screen apps.
    public static let fullScreenPolicy = SettingKey<FullScreenPolicy>(.general, "fullScreenPolicy", default: .alertsAndHUD)
    /// General ▸ Hide in these apps.
    public static let excludedBundleIDs = SettingKey<[String]>(.general, "excludedBundleIDs", default: [])
    /// General ▸ Demo mode: no personal data, no sounds.
    public static let demoMode = SettingKey<Bool>(.general, "demoMode", default: false)
    /// General ▸ Demo mode ▸ Redact calendar titles.
    public static let demoRedactsCalendar = SettingKey<Bool>(.general, "demoRedactsCalendar", default: true)
    /// General ▸ Show the menu bar icon.
    public static let showsMenuBarIcon = SettingKey<Bool>(.general, "showsMenuBarIcon", default: true)
    /// System UI sounds: "Pop" on file caught, "Tink" on to-do done (DESIGN.md §14.3). Muted in Demo mode.
    public static let uiSounds = SettingKey<Bool>(.general, "uiSounds", default: false)

    // Displays
    /// General ▸ Show on: which displays get a panel.
    public static let displaySelection = SettingKey<DisplaySelection>(.displays, "selection", default: .builtIn)
    /// General ▸ Displays: per-display style and toggles.
    public static let perDisplay = SettingKey<[DisplayKey: DisplayPreferences]>(.displays, "perDisplay", default: [:])

    // Appearance
    /// Appearance ▸ Accent.
    public static let accent = SettingKey<AccentSource>(.appearance, "accent", default: .automatic)
    /// Appearance ▸ Text size.
    public static let textSize = SettingKey<CrannyTextSize>(.appearance, "textSize", default: .standard)
    /// Appearance ▸ Motion.
    public static let motion = SettingKey<MotionPersonality>(.appearance, "motion", default: .standard)
    /// Appearance ▸ Ambient light.
    public static let ambience = SettingKey<AmbienceLevel>(.appearance, "ambience", default: .subtle)
    /// Appearance ▸ Ambient light ▸ Effect.
    public static let effect = SettingKey<AmbientEffect>(.appearance, "effect", default: .aurora)
    /// Appearance ▸ Album glow behind artwork.
    public static let albumGlow = SettingKey<Bool>(.appearance, "albumGlow", default: true)
    /// Appearance ▸ Underglow (Vivid ambience only).
    public static let underglow = SettingKey<Bool>(.appearance, "underglow", default: true)
    /// Appearance ▸ Progress rim around the closed notch.
    public static let progressRim = SettingKey<Bool>(.appearance, "progressRim", default: false)
    /// Appearance ▸ Translucent background.
    public static let translucentBackground = SettingKey<Bool>(.appearance, "translucentBackground", default: false)
    /// Appearance ▸ Liquid Glass island (macOS 26+, displays without a notch).
    public static let glassIsland = SettingKey<Bool>(.appearance, "glassIsland", default: false)
    /// Appearance ▸ Buttons: capsule or rounded.
    public static let buttonShape = SettingKey<ButtonShapeStyle>(.appearance, "buttonShape", default: .capsule)
    /// Appearance ▸ Widgets: cards or flat.
    public static let widgetStyle = SettingKey<WidgetStyle>(.appearance, "widgetStyle", default: .cards)
    /// Appearance ▸ Density.
    public static let density = SettingKey<NookDensity>(.appearance, "density", default: .standard)
    /// Appearance ▸ Panel padding, ±4 pt on top of the density.
    public static let panelPaddingTune = SettingKey<Double>(.appearance, "panelPaddingTune", default: 0)
    /// Appearance ▸ Notch fit, per display model: in the Appearance namespace so "Reset Appearance…" resets it and
    /// "Reset General…" (which resets `.displays`) keeps it (DESIGN.md §11.1).
    public static let notchFit = SettingKey<[String: NotchFit]>(.appearance, "notchFit", default: [:])
    /// Appearance ▸ On displays without a notch.
    public static let noNotchStyle = SettingKey<NoNotchStyle>(.appearance, "noNotchStyle", default: .floatingIsland)
    /// Appearance ▸ Handle on displays without a notch.
    public static let handleVisibility = SettingKey<HandleVisibility>(.appearance, "handleVisibility", default: .visible)
    /// Appearance ▸ Typing effect in Notes.
    public static let typingEffect = SettingKey<Bool>(.appearance, "typingEffect", default: true)

    // Layout & Widgets (code namespace `nook`)
    /// Layout & Widgets: the grid pages (Home first).
    public static let pages = SettingKey<[NookPage]>(.nook, "pages", default: [NookPreset.listener.page])
    /// The page the Nook showed last (it opens there again).
    public static let lastPage = SettingKey<PageID>(.nook, "lastPage", default: .nook)

    // Live Activities
    /// Live Activities: per-kind enable and "Peek on change".
    public static let activityPreferences = SettingKey<[ActivityID: ActivityPreference]>(.activities, "preferences", default: [:])
    /// The user's order (ties within a priority class).
    public static let activityOrder = SettingKey<[ActivityID]>(.activities, "order", default: [])
    /// Live Activities ▸ Peek duration (seconds).
    public static let peekDuration = SettingKey<Double>(.activities, "peekDuration", default: HoverIntent.peekAutoDismiss)
    /// Live Activities ▸ Quick peek on hover.
    public static let quickPeekOnHover = SettingKey<Bool>(.activities, "quickPeekOnHover", default: true)
    /// Live Activities ▸ Show a second activity beside the notch (the satellite).
    public static let satellite = SettingKey<Bool>(.activities, "satellite", default: true)
    /// Seconds; 0 = never. Collapses compact to closed (keeps the satellite).
    public static let compactInactivityTimeout = SettingKey<Double>(.activities, "compactInactivityTimeout", default: 0)
    /// Live Activities ▸ Swipe up to dismiss.
    public static let swipeToDismiss = SettingKey<Bool>(.activities, "swipeToDismiss", default: true)
    /// Live Activities ▸ Bring a dismissed activity back when it changes.
    public static let autoUnhide = SettingKey<Bool>(.activities, "autoUnhide", default: true)
    /// Live Activities ▸ Retract the wings when the pointer nears the menu bar.
    public static let menuBarCourtesy = SettingKey<Bool>(.activities, "menuBarCourtesy", default: true)
    /// Menu bar extra ▸ Pause Live Activities. nil = not paused; `.distantFuture` = until resumed.
    public static let pausedUntil = SettingKey<Date?>(.activities, "pausedUntil", default: nil)

    // Gestures
    /// Gestures ▸ Swipe sideways to change track.
    public static let trackSwipe = SettingKey<Bool>(.gestures, "trackSwipe", default: true)
    /// Gestures ▸ Invert the track swipe.
    public static let invertTrackSwipe = SettingKey<Bool>(.gestures, "invertTrackSwipe", default: false)
    /// Gestures ▸ Swipe down to open, up to close.
    public static let swipeOpenClose = SettingKey<Bool>(.gestures, "swipeOpenClose", default: true)
    /// Gestures ▸ Sensitivity, 0.5…1.5.
    public static let gestureSensitivity = SettingKey<Double>(.gestures, "sensitivity", default: 1)
    /// Gestures ▸ Haptic feedback.
    public static let haptics = SettingKey<Bool>(.gestures, "haptics", default: true)

    // Keyboard
    /// User overrides; a missing entry means the shortcut's `defaultCombo`; an explicit nil means "off".
    public static let shortcuts = SettingKey<[ShortcutID: KeyCombo?]>(.keyboard, "shortcuts", default: [:])
    /// `CaptureTarget.id` ("notes", "todos") or nil = off.
    public static let typeToCapture = SettingKey<String?>(.keyboard, "typeToCapture", default: "notes")

    // Onboarding & updates
    /// The version whose Welcome flow the user finished (nil = never).
    public static let onboardingCompletedVersion = SettingKey<String?>(.onboarding, "completedVersion", default: nil)
    /// The interactive tutorial was finished.
    public static let tutorialCompleted = SettingKey<Bool>(.onboarding, "tutorialCompleted", default: false)
    /// About ▸ Check for updates automatically.
    public static let checksForUpdates = SettingKey<Bool>(.updates, "automatic", default: true)
    /// About ▸ Include pre-releases.
    public static let includesPrereleases = SettingKey<Bool>(.updates, "prereleases", default: false)
    /// When updates were last checked.
    public static let lastUpdateCheck = SettingKey<Date?>(.updates, "lastCheck", default: nil)
}
