// CrannyCore/Contracts/Contributions.swift
// Everything else a module can contribute: settings panes, ⌘K commands, global shortcuts,
// type-to-capture targets and the permissions it may ask for.
import SwiftUI

// MARK: - Settings pages

/// Sidebar group in the Settings window (DESIGN.md §11.1).
public nonisolated enum SettingsGroup: Int, Comparable, Sendable {
    case top = 0, notch = 1, features = 2, bottom = 3
    /// Sidebar order: top, notch, features, bottom.
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The system colour behind the white glyph of a sidebar icon (20 × 20, r 5).
public nonisolated enum SettingsIconTint: String, Sendable {
    case gray, purple, indigo, blue, pink, teal, orange, red, green
    /// The system colour behind the white glyph.
    public var color: Color {
        switch self {
        case .gray: .gray
        case .purple: .purple
        case .indigo: .indigo
        case .blue: .blue
        case .pink: .pink
        case .teal: .teal
        case .orange: .orange
        case .red: .red
        case .green: .green
        }
    }
}

/// Which notch state the Settings preview stage auto-selects for a pane (DESIGN.md §11.2).
public nonisolated enum PreviewStageState: String, Sendable, CaseIterable {
    case closed, activity, peek, open, hud
}

/// A Settings pane contributed with `registry.add(settingsPage:)` (DESIGN.md §11.1). The shell lays out the
/// sidebar, the search index and the preview stage; the module supplies the view.
public struct SettingsPage: Identifiable {
    /// Stable identifier (deep links: `AppControl.openSettings(_:)`, `--qa-settings`).
    public let id: SettingsPageID
    /// The sidebar title, already localized.
    public let title: String
    /// The sidebar glyph (DESIGN.md §14.1).
    public let symbol: String
    /// The colour behind the sidebar glyph.
    public let tint: SettingsIconTint
    /// The sidebar group the pane belongs to.
    public let group: SettingsGroup
    /// Sort key within the group.
    public let order: Int
    /// Localized search terms. Shell panes are indexed by their row labels; a MODULE pane is an opaque view,
    /// so it must list its row labels here too ("volume" → HUD, "lead time" → Calendar).
    public let keywords: [String]
    /// Settings namespaces reset by "Reset ‹Pane›…". Empty = the registering module (filled by the registry).
    public var namespaces: [ModuleID]
    /// nil = no preview stage (Permissions, About).
    public let previewState: PreviewStageState?
    /// Builds the pane (an ordinary Settings window view: system controls, `crannySettingRow` conventions).
    public let makeView: @MainActor () -> AnyView

    /// A pane; `namespaces` empty = the registering module, `previewState` nil = no preview stage.
    public init(id: SettingsPageID, title: String, symbol: String, tint: SettingsIconTint, group: SettingsGroup,
                order: Int, keywords: [String] = [], namespaces: [ModuleID] = [], previewState: PreviewStageState? = .open,
                makeView: @escaping @MainActor () -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.tint = tint; self.group = group
        self.order = order; self.keywords = keywords; self.namespaces = namespaces
        self.previewState = previewState; self.makeView = makeView
    }
}

// MARK: - Command palette (⌘K)

/// One ⌘K result. Providers build them on every keystroke, so they are plain values.
public struct PaletteCommand: Identifiable {
    /// Stable identifier (ranking memory, tests).
    public let id: CommandID
    /// The action, localized, sentence case ("Start 25-minute timer").
    public let title: String
    /// The owner, shown as a tertiary caption ("Timer").
    public let kind: String
    /// The result's glyph.
    public let symbol: String
    /// Extra localized search terms.
    public let keywords: [String]
    /// The key combination shown as a key cap, if the action has one.
    public let shortcut: KeyCombo?
    /// Runs the command (the palette closes first).
    public let perform: @MainActor () -> Void
    /// A command.
    public init(id: CommandID, title: String, kind: String, symbol: String, keywords: [String] = [],
                shortcut: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.kind = kind; self.symbol = symbol
        self.keywords = keywords; self.shortcut = shortcut; self.perform = perform
    }
}

/// Queried on every keystroke in the palette: must be fast (in-memory filtering only).
@MainActor public protocol PaletteCommandProvider: AnyObject {
    /// The commands that match `query` (empty = the provider's suggestions), ranked by the palette.
    func commands(matching query: String) -> [PaletteCommand]
}

// MARK: - Keyboard

/// A key combination in Carbon terms (virtual key code + modifiers) so the shell can register it
/// with `RegisterEventHotKey` (no Accessibility permission needed; verified on macOS 27).
public nonisolated struct KeyCombo: Codable, Hashable, Sendable {
    /// Modifier keys, independent of Carbon's bit layout (the shell converts them).
    public nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        /// The option bits.
        public let rawValue: Int
        /// Modifiers from raw bits.
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// ⌘
        public static let command = Modifiers(rawValue: 1 << 0)
        /// ⌥
        public static let option = Modifiers(rawValue: 1 << 1)
        /// ⌃
        public static let control = Modifiers(rawValue: 1 << 2)
        /// ⇧
        public static let shift = Modifiers(rawValue: 1 << 3)
    }
    /// The virtual key code, a `kVK_*` constant (Carbon HIToolbox/Events.h).
    public var keyCode: UInt16
    /// The modifier keys held with it.
    public var modifiers: Modifiers
    /// Display string for key caps ("⌃⌥N"), built by the caller from the current keyboard layout.
    public var display: String
    /// A combination with its key-cap text.
    public init(keyCode: UInt16, modifiers: Modifiers, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
    }
    /// ⌃⌥N — DESIGN.md decision #11 (⌥⌘N is Finder's New Smart Folder; ⌃⌥Space switches input sources).
    public static let openNookDefault = KeyCombo(keyCode: 45 /* kVK_ANSI_N */, modifiers: [.control, .option], display: "⌃⌥N")
}

/// A system-wide shortcut contributed by a module ("New note"). The shell registers it and stores the
/// user's binding in `CoreSettings.shortcuts`; `defaultCombo == nil` means "off until the user sets one".
public struct GlobalShortcut: Identifiable {
    /// Stable identifier; the user's binding is stored under it in `CoreSettings.shortcuts`.
    public let id: ShortcutID
    /// The action's name in Settings ▸ Keyboard, localized.
    public let title: String
    /// The binding until the user changes it; nil = off.
    public let defaultCombo: KeyCombo?
    /// Runs the action when the shortcut fires (on the main actor).
    public let perform: @MainActor () -> Void
    /// A shortcut, off by default unless `defaultCombo` is set.
    public init(id: ShortcutID, title: String, defaultCombo: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.defaultCombo = defaultCombo; self.perform = perform
    }
}

/// Type-to-capture (DESIGN.md §7.5): if the Nook was opened by the keyboard and nothing is focused, the
/// first printable keys go to the target the user chose (Notes or To-dos).
public struct CaptureTarget: Identifiable {
    /// The value stored in `CoreSettings.typeToCapture` ("notes", "todos").
    public let id: String
    /// The target's name in Settings ▸ Keyboard, localized.
    public let title: String
    /// The target's glyph.
    public let symbol: String
    /// Receives the first characters; must create the item, focus its editor and return the widget to focus.
    public let capture: @MainActor (String) -> WidgetID
    /// The widget that shows what `capture` creates. While it is on no page the shell does not capture (the item
    /// would be invisible); nil = not known, always captured. Set by `init(id:title:symbol:widget:capture:)`
    /// (Additions/PhaseC-CaptureTargetWidget.swift).
    public let widget: WidgetID?
    public init(id: String, title: String, symbol: String, capture: @escaping @MainActor (String) -> WidgetID) {
        self.id = id; self.title = title; self.symbol = symbol; self.capture = capture; self.widget = nil
    }
}

/// A permission a module may request, with its localized one-line reason (Permissions pane, onboarding).
public nonisolated struct PermissionUse: Hashable, Sendable {
    /// The permission.
    public let kind: PermissionKind
    /// The module that may ask for it.
    public let module: ModuleID
    public let reason: String               // "Show your events in Cranny. Cranny never edits or uploads them."
    public init(kind: PermissionKind, module: ModuleID, reason: String) {
        self.kind = kind; self.module = module; self.reason = reason
    }
}
