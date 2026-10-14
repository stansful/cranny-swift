// CrannyCore/Contracts/Contributions.swift
// Everything else a module can contribute: settings panes, ⌘K commands, global shortcuts,
// type-to-capture targets and the permissions it may ask for.
import SwiftUI

// MARK: - Settings pages

/// Sidebar group in the Settings window (DESIGN.md §11.1).
public nonisolated enum SettingsGroup: Int, Comparable, Sendable {
    case top = 0, notch = 1, features = 2, bottom = 3
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// The system colour behind the white glyph of a sidebar icon (20 × 20, r 5).
public nonisolated enum SettingsIconTint: String, Sendable {
    case gray, purple, indigo, blue, pink, teal, orange, red, green
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

public struct SettingsPage: Identifiable {
    public let id: SettingsPageID
    public let title: String                 // localized
    public let symbol: String
    public let tint: SettingsIconTint
    public let group: SettingsGroup
    public let order: Int
    /// Localized search terms. Shell panes are indexed by their row labels; a MODULE pane is an opaque view,
    /// so it must list its row labels here too ("volume" → HUD, "lead time" → Calendar).
    public let keywords: [String]
    /// Settings namespaces reset by "Reset ‹Pane›…". Empty = the registering module (filled by the registry).
    public var namespaces: [ModuleID]
    /// nil = no preview stage (Permissions, About).
    public let previewState: PreviewStageState?
    public let makeView: @MainActor () -> AnyView

    public init(id: SettingsPageID, title: String, symbol: String, tint: SettingsIconTint, group: SettingsGroup,
                order: Int, keywords: [String] = [], namespaces: [ModuleID] = [], previewState: PreviewStageState? = .open,
                makeView: @escaping @MainActor () -> AnyView) {
        self.id = id; self.title = title; self.symbol = symbol; self.tint = tint; self.group = group
        self.order = order; self.keywords = keywords; self.namespaces = namespaces
        self.previewState = previewState; self.makeView = makeView
    }
}

// MARK: - Command palette (⌘K)

public struct PaletteCommand: Identifiable {
    public let id: CommandID
    public let title: String                 // "Start 25-minute timer"
    public let kind: String                  // "Timer" (caption, tertiary)
    public let symbol: String
    public let keywords: [String]
    public let shortcut: KeyCombo?
    public let perform: @MainActor () -> Void
    public init(id: CommandID, title: String, kind: String, symbol: String, keywords: [String] = [],
                shortcut: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.kind = kind; self.symbol = symbol
        self.keywords = keywords; self.shortcut = shortcut; self.perform = perform
    }
}

/// Queried on every keystroke in the palette: must be fast (in-memory filtering only).
@MainActor public protocol PaletteCommandProvider: AnyObject {
    func commands(matching query: String) -> [PaletteCommand]
}

// MARK: - Keyboard

/// A key combination in Carbon terms (virtual key code + modifiers) so the shell can register it
/// with `RegisterEventHotKey` (no Accessibility permission needed; verified on macOS 27).
public nonisolated struct KeyCombo: Codable, Hashable, Sendable {
    public nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }
    public var keyCode: UInt16          // kVK_* (Carbon HIToolbox/Events.h)
    public var modifiers: Modifiers
    /// Display string for key caps ("⌃⌥N"), built by the caller from the current keyboard layout.
    public var display: String
    public init(keyCode: UInt16, modifiers: Modifiers, display: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.display = display
    }
    /// ⌃⌥N — DESIGN.md decision #11 (⌥⌘N is Finder's New Smart Folder; ⌃⌥Space switches input sources).
    public static let openNookDefault = KeyCombo(keyCode: 45 /* kVK_ANSI_N */, modifiers: [.control, .option], display: "⌃⌥N")
}

/// A system-wide shortcut contributed by a module ("New note"). The shell registers it and stores the
/// user's binding in `CoreSettings.shortcuts`; `defaultCombo == nil` means "off until the user sets one".
public struct GlobalShortcut: Identifiable {
    public let id: ShortcutID
    public let title: String
    public let defaultCombo: KeyCombo?
    public let perform: @MainActor () -> Void
    public init(id: ShortcutID, title: String, defaultCombo: KeyCombo? = nil, perform: @escaping @MainActor () -> Void) {
        self.id = id; self.title = title; self.defaultCombo = defaultCombo; self.perform = perform
    }
}

/// Type-to-capture (DESIGN.md §7.5): if the Nook was opened by the keyboard and nothing is focused, the
/// first printable keys go to the target the user chose (Notes or To-dos).
public struct CaptureTarget: Identifiable {
    public let id: String                   // "notes", "todos"
    public let title: String
    public let symbol: String
    /// Receives the first characters; must create the item, focus its editor and return the widget to focus.
    public let capture: @MainActor (String) -> WidgetID
    public init(id: String, title: String, symbol: String, capture: @escaping @MainActor (String) -> WidgetID) {
        self.id = id; self.title = title; self.symbol = symbol; self.capture = capture
    }
}

/// A permission a module may request, with its localized one-line reason (Permissions pane, onboarding).
public nonisolated struct PermissionUse: Hashable, Sendable {
    public let kind: PermissionKind
    public let module: ModuleID
    public let reason: String               // "Show your events in Cranny. Cranny never edits or uploads them."
    public init(kind: PermissionKind, module: ModuleID, reason: String) {
        self.kind = kind; self.module = module; self.reason = reason
    }
}
