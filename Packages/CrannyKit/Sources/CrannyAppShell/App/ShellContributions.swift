// CrannyAppShell/App/ShellContributions.swift — the shell's own contributions (ARCHITECTURE.md §10.0), WP16.
// Global shortcuts: Open Cranny (⌃⌥N) and Toggle pin → the overlay; Pause activities → `PauseController`.
// ⌘K: Pause Live Activities for 1 hour (or Resume), Demo mode, Keep Cranny open, Show tutorial, and every
// Settings pane — and nothing else. Commands resolve state at query time, so their titles always say what they do.
// No VoiceOver announcements: DESIGN.md §16 keeps them for P1 alerts and pipeline completion.
import Carbon.HIToolbox
import CrannyCore
import Foundation

@MainActor enum ShellContributions {
    static func register(in registry: ModuleRegistry, overlay: OverlayCoordinator) {
        let settings = registry.services.settings
        let pause = PauseController(settings: settings)
        let demo = DemoMode(settings: settings)
        registry.add(shortcut: GlobalShortcut(
            id: .openNook, title: String(localized: "Open Cranny", bundle: .module, comment: "Menu bar and Settings ▸ Keyboard: item and shortcut that open the panel"),
            defaultCombo: .openNookDefault) { [weak overlay] in overlay?.toggleOpen() })
        registry.add(shortcut: GlobalShortcut(
            id: .togglePin, title: String(localized: "Toggle pin", bundle: .module, comment: "Settings ▸ Keyboard: shortcut name (pins or unpins the open panel)"),
            defaultCombo: nil) { [weak overlay] in overlay?.togglePinned() })
        registry.add(shortcut: GlobalShortcut(
            id: .pauseActivities,
            title: String(localized: "Pause activities", bundle: .module,
                          comment: "Settings ▸ Keyboard: shortcut name (pauses Live Activities for 1 hour, or resumes them)"),
            defaultCombo: nil) { pause.toggle() })
        registry.add(commands: ShellCommands(registry: registry, overlay: overlay, pause: pause, demo: demo))
    }
}

/// The shell's ⌘K provider. In-memory filtering only (it runs on every keystroke).
@MainActor final class ShellCommands: PaletteCommandProvider {
    private weak var registry: ModuleRegistry?
    private weak var overlay: OverlayCoordinator?
    private let pause: PauseController
    private let demo: DemoMode

    init(registry: ModuleRegistry, overlay: OverlayCoordinator?, pause: PauseController, demo: DemoMode) {
        self.registry = registry; self.overlay = overlay; self.pause = pause; self.demo = demo
    }

    /// An empty query lists the actions; typing also searches every Settings pane.
    func commands(matching query: String) -> [PaletteCommand] {
        let tokens = Self.tokens(query)
        let candidates = tokens.isEmpty ? actions() : actions() + panes()
        return candidates.filter { Self.matches($0, tokens: tokens) }
    }

    // MARK: Matching (pure)

    static func tokens(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every word of the query appears in the title, the kind or a keyword (case- and diacritic-insensitive).
    static func matches(_ command: PaletteCommand, tokens: [String]) -> Bool {
        let haystack = ([command.title, command.kind] + command.keywords).joined(separator: " ")
        return tokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    // MARK: Actions

    private func actions() -> [PaletteCommand] {
        let kind = "Cranny"
        let pause = self.pause, demo = self.demo
        var result: [PaletteCommand] = []
        if pause.isPaused {
            result.append(PaletteCommand(
                id: "shell.resume", title: String(localized: "Resume Live Activities", bundle: .module, comment: "Menu bar and ⌘K: ends a pause of Live Activities"),
                kind: kind, symbol: "play.fill", keywords: Self.keywords(.pause)) { pause.resume() })
        } else {
            result.append(PaletteCommand(
                id: "shell.pause", title: String(localized: "Pause Live Activities for 1 hour", bundle: .module,
                                                   comment: "⌘K: command that pauses Live Activities for one hour"),
                kind: kind, symbol: "pause.fill", keywords: Self.keywords(.pause)) { pause.pause(.oneHour) })
        }
        result.append(PaletteCommand(
            id: "shell.demo",
            title: demo.isOn ? String(localized: "Turn off demo mode", bundle: .module, comment: "⌘K: command that turns Demo mode off")
                             : String(localized: "Turn on demo mode", bundle: .module, comment: "⌘K: command that turns Demo mode on"),
            kind: kind, symbol: "sparkles", keywords: Self.keywords(.demo)) { demo.toggle() })
        let pinned = overlay?.isPinned ?? false
        result.append(PaletteCommand(
            id: "shell.pin",
            title: pinned ? String(localized: "Unpin Cranny", bundle: .module, comment: "⌘K: command (lets the open panel close again)")
                          : String(localized: "Keep Cranny open", bundle: .module, comment: "⌘K: command (pins the open panel)"),
            kind: kind, symbol: pinned ? "pin.fill" : "pin", keywords: Self.keywords(.pin),
            shortcut: KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command], display: "⌘P")) { [weak overlay] in
                overlay?.togglePinned()
            })
        result.append(PaletteCommand(
            id: "shell.tutorial", title: String(localized: "Show tutorial", bundle: .module, comment: "⌘K: command (replays the interactive tutorial)"),
            kind: kind, symbol: "cursorarrow.motionlines", keywords: Self.keywords(.tutorial)) { [weak registry] in
                registry?.services.app.startTutorial()
            })
        return result
    }

    /// Every Settings pane, in sidebar order: the shell's own panes and the ones modules registered.
    private func panes() -> [PaletteCommand] {
        let kind = String(localized: "Settings", bundle: .module, comment: "⌘K: result kind of the Settings pane commands")
        let modulePages = (registry?.settingsPages ?? []).map {
            ShellPane(id: $0.id, title: $0.title, symbol: $0.symbol, group: $0.group, order: $0.order, keywords: $0.keywords)
        }
        let all = (ShellPane.shellPanes + modulePages.filter { page in !ShellPane.shellPanes.contains { $0.id == page.id } })
            .sorted { ($0.group, $0.order) < ($1.group, $1.order) }
        return all.map { pane in
            PaletteCommand(id: CommandID("shell.settings.\(pane.id.rawValue)"), title: pane.title, kind: kind, symbol: pane.symbol,
                           keywords: pane.keywords) { [weak registry] in registry?.services.app.openSettings(pane.id) }
        }
    }

    private enum Topic { case pause, demo, pin, tutorial }

    /// Localized search words, comma-separated in the catalog so translators can add synonyms.
    private static func keywords(_ topic: Topic) -> [String] {
        let list = switch topic {
        case .pause: String(localized: "pause, silence, quiet, resume, live activities", bundle: .module,
                            comment: "⌘K: search words for Pause/Resume Live Activities, comma-separated")
        case .demo: String(localized: "demo, presentation, recording, screen sharing", bundle: .module,
                           comment: "⌘K: search words for Demo mode, comma-separated")
        case .pin: String(localized: "pin, keep open, stay", bundle: .module, comment: "⌘K: search words for Keep Cranny open, comma-separated")
        case .tutorial: String(localized: "tutorial, tour, help, learn", bundle: .module, comment: "⌘K: search words for Show tutorial, comma-separated")
        }
        return ShellPane.split(list)
    }
}

/// A Settings pane as the palette lists it. The shell's own panes live in CrannySettingsUI (not importable as a
/// list), so their names and symbols are restated here, as DESIGN.md §11.1 gives them.
struct ShellPane {
    let id: SettingsPageID
    let title: String
    let symbol: String
    let group: SettingsGroup
    let order: Int
    let keywords: [String]

    static var shellPanes: [ShellPane] {
        [
            ShellPane(id: .general, title: String(localized: "General", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "gearshape.fill", group: .top, order: 0,
                      keywords: split(String(localized: "launch at login, displays, hover, full screen, demo, sounds, menu bar icon, updates", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ General, comma-separated"))),
            ShellPane(id: .appearance, title: String(localized: "Appearance", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "paintbrush.fill", group: .top, order: 1,
                      keywords: split(String(localized: "accent, color, text size, motion, ambient light, notch fit, density", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Appearance, comma-separated"))),
            ShellPane(id: .keyboard, title: String(localized: "Keyboard", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "keyboard", group: .top, order: 2,
                      keywords: split(String(localized: "shortcuts, hot keys, keys", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Keyboard, comma-separated"))),
            ShellPane(id: .nookAndWidgets, title: String(localized: "Layout & Widgets", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "square.grid.2x2.fill", group: .notch, order: 0,
                      keywords: split(String(localized: "widgets, pages, grid, layout", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Layout & Widgets, comma-separated"))),
            ShellPane(id: .liveActivities, title: String(localized: "Live Activities", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "capsule.tophalf.filled", group: .notch, order: 1,
                      keywords: split(String(localized: "peek, priority, satellite, activities", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Live Activities, comma-separated"))),
            ShellPane(id: .gestures, title: String(localized: "Gestures", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "hand.draw.fill", group: .notch, order: 3,
                      keywords: split(String(localized: "swipe, trackpad, haptics", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Gestures, comma-separated"))),
            ShellPane(id: .permissions, title: String(localized: "Permissions", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "hand.raised.fill", group: .bottom, order: 0,
                      keywords: split(String(localized: "privacy, access, calendar, camera, accessibility", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ Permissions, comma-separated"))),
            ShellPane(id: .about, title: String(localized: "About", bundle: .module, comment: "⌘K: Settings pane name (as in the Settings sidebar)"),
                      symbol: "info.circle.fill", group: .bottom, order: 1,
                      keywords: split(String(localized: "version, updates, license, acknowledgments", bundle: .module,
                                             comment: "⌘K: search words for Settings ▸ About, comma-separated"))),
        ]
    }

    /// "a, b ,c" → ["a", "b", "c"].
    static func split(_ list: String) -> [String] {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
