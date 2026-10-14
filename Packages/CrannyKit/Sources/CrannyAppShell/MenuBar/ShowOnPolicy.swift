// CrannyAppShell/MenuBar/ShowOnPolicy.swift — the pure logic of the menu bar's Show On ▸ submenu (DESIGN.md §13):
// which connected displays show Cranny under the current settings, and what one click on a display (or on
// "Display with the Pointer") writes back into `CoreSettings.displaySelection` / `perDisplay`.
// Mirrors the eligibility rules of `OverlayCoordinator.panelScreens` (ARCHITECTURE.md §4.9) on plain values.
import CrannyCore
import Foundation

/// One connected display, in `NSScreen.screens` order (the first one is the primary display).
nonisolated struct ConnectedDisplay: Equatable, Sendable, Identifiable {
    var key: DisplayKey
    /// `NSScreen.localizedName`, made unique by `ShowOnPolicy.menuTitles`.
    var name: String
    var isBuiltIn: Bool
    var hasNotch: Bool
    var id: DisplayKey { key }
}

nonisolated struct ShowOnPolicy: Equatable, Sendable {
    var selection: DisplaySelection
    var perDisplay: [DisplayKey: DisplayPreferences]
    var noNotchStyle: NoNotchStyle

    /// The displays that get a panel: the selection, minus displays without a notch whose style is Off.
    func shownKeys(on displays: [ConnectedDisplay]) -> Set<DisplayKey> {
        Set(selected(on: displays).filter { !isStyledOff($0) }.map(\.key))
    }

    /// Whether the menu offers "Display with the Pointer" (meaningless with a single display).
    static func offersPointerMode(on displays: [ConnectedDisplay]) -> Bool { displays.count > 1 }

    /// A display row is disabled when unchecking it would leave Cranny on no display at all.
    func canToggle(_ key: DisplayKey, on displays: [ConnectedDisplay]) -> Bool {
        let shown = shownKeys(on: displays)
        return !(selection != .pointer && shown == [key])
    }

    /// The settings after one click on a display row: checked → unchecked and vice versa. In pointer mode the
    /// rows read as unchecked and a click shows Cranny on that display only. A display that is checked on but has
    /// its style set to Off (no notch) gets a visible style again, so the checkmark tells the truth.
    func toggling(_ key: DisplayKey, on displays: [ConnectedDisplay]) -> ShowOnPolicy {
        guard let display = displays.first(where: { $0.key == key }), canToggle(key, on: displays) else { return self }
        var shown = selection == .pointer ? [] : shownKeys(on: displays)
        let turningOn = !shown.contains(key)
        if turningOn { shown.insert(key) } else { shown.remove(key) }

        var next = self
        next.selection = Self.normalized(shown, on: displays, keeping: selection)
        if turningOn, isStyledOff(display) {
            var preferences = perDisplay[key] ?? DisplayPreferences()
            preferences.style = .floatingIsland
            next.perDisplay[key] = preferences
        }
        return next
    }

    /// "Display with the Pointer": on → `.pointer`; off again → every display.
    func togglingPointerMode() -> ShowOnPolicy {
        var next = self
        next.selection = selection == .pointer ? .all : .pointer
        return next
    }

    // MARK: Private

    private func selected(on displays: [ConnectedDisplay]) -> [ConnectedDisplay] {
        switch selection {
        case .builtIn:
            return [displays.first(where: \.isBuiltIn) ?? displays.first].compactMap { $0 }
        case .pointer, .all:
            return displays
        case .custom(let keys):
            let chosen = displays.filter { keys.contains($0.key) }
            return chosen.isEmpty ? Array(displays.prefix(1)) : chosen
        }
    }

    private func isStyledOff(_ display: ConnectedDisplay) -> Bool {
        !display.hasNotch && (perDisplay[display.key]?.style ?? noNotchStyle) == .off
    }

    /// The simplest selection that shows exactly `keys`: Built-in (the default), All, or a custom list in screen
    /// order. A custom list keeps the keys of disconnected displays it had, so they come back when reconnected.
    private static func normalized(_ keys: Set<DisplayKey>, on displays: [ConnectedDisplay],
                                   keeping previous: DisplaySelection) -> DisplaySelection {
        let builtInOrPrimary = (displays.first(where: \.isBuiltIn) ?? displays.first).map { Set([$0.key]) } ?? []
        var disconnected: [DisplayKey] = []
        if case .custom(let old) = previous {
            disconnected = old.filter { key in !displays.contains { $0.key == key } }
        }
        if disconnected.isEmpty {
            if keys == builtInOrPrimary { return .builtIn }
            if displays.count > 1, keys == Set(displays.map(\.key)) { return .all }
        }
        return .custom(displays.map(\.key).filter(keys.contains) + disconnected)
    }
}

extension ShowOnPolicy {
    /// Display names for the menu: `NSScreen.localizedName`, with " 2", " 3"… appended to repeated names so two
    /// identical monitors stay distinguishable.
    static func menuTitles(for names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        let repeated = Set(Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys)
        return names.map { name in
            guard repeated.contains(name) else { return name }
            let n = (seen[name] ?? 0) + 1
            seen[name] = n
            return n == 1 ? name : "\(name) \(n)"
        }
    }
}
