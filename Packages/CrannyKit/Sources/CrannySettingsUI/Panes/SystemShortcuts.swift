// CrannySettingsUI/Panes/SystemShortcuts.swift — a best-effort check of a Cranny shortcut against the enabled macOS
// shortcuts (DESIGN.md §11.1 Keyboard; ARCHITECTURE §10.15). `RegisterEventHotKey` does not fail on a system combo,
// so Settings reads the `AppleSymbolicHotKeys` dictionary of the `com.apple.symbolichotkeys` domain (read-only; readable
// on macOS 27, format observed there: `{ "<id>": { enabled, value: { parameters: [ascii, keyCode, NSEvent flags] } } }`).
// The domain lists only shortcuts the user changed, so a few well-known defaults fill the gaps. Parsing is pure (tested).
import AppKit
import CrannyCore
import Foundation

/// One macOS shortcut that is turned on.
struct SystemShortcut: Equatable {
    let id: Int
    let keyCode: UInt16
    let modifiers: KeyCombo.Modifiers

    func matches(_ combo: KeyCombo) -> Bool { combo.keyCode == keyCode && combo.modifiers == modifiers }
}

enum SystemShortcuts {
    /// The enabled shortcuts: the user's entries from the domain, plus the defaults of well-known ids it does not list.
    static func enabled(from domain: [String: Any]?) -> [SystemShortcut] {
        var byID: [Int: SystemShortcut?] = [:]
        for (key, raw) in domain ?? [:] {
            guard let id = Int(key), let entry = raw as? [String: Any] else { continue }
            byID[id] = parse(id: id, entry: entry)
        }
        for (id, shortcut) in defaults where byID[id] == nil { byID[id] = shortcut }
        return byID.values.compactMap { $0 }.sorted { $0.id < $1.id }
    }

    /// One domain entry; nil when it is disabled, has no key or is not a "standard" shortcut.
    static func parse(id: Int, entry: [String: Any]) -> SystemShortcut? {
        guard (entry["enabled"] as? Bool) ?? (entry["enabled"] as? NSNumber)?.boolValue ?? false,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = (parameters[1] as? NSNumber)?.intValue, keyCode != 0xFFFF, keyCode >= 0,
              let flags = (parameters[2] as? NSNumber)?.intValue else { return nil }
        return SystemShortcut(id: id, keyCode: UInt16(keyCode), modifiers: modifiers(flags))
    }

    /// `NSEvent.ModifierFlags` raw bits → `KeyCombo.Modifiers` (Fn, which arrows and F-keys carry, is ignored).
    static func modifiers(_ flags: Int) -> KeyCombo.Modifiers {
        var modifiers: KeyCombo.Modifiers = []
        if flags & (1 << 17) != 0 { modifiers.insert(.shift) }
        if flags & (1 << 18) != 0 { modifiers.insert(.control) }
        if flags & (1 << 19) != 0 { modifiers.insert(.option) }
        if flags & (1 << 20) != 0 { modifiers.insert(.command) }
        return modifiers
    }

    /// The first enabled macOS shortcut that uses `combo`.
    static func conflict(for combo: KeyCombo, in shortcuts: [SystemShortcut]) -> SystemShortcut? {
        shortcuts.first { $0.matches(combo) }
    }

    /// Reads the domain (no prompt: an ordinary preferences read). nil when it cannot be read.
    static func readDomain() -> [String: Any]? {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
    }

    /// macOS defaults of shortcuts that collide most often (screenshots, Spaces, input sources, Spotlight).
    static let defaults: [Int: SystemShortcut] = {
        let list: [(Int, UInt16, KeyCombo.Modifiers)] = [
            (28, 20, [.shift, .command]), (29, 20, [.control, .shift, .command]),
            (30, 21, [.shift, .command]), (31, 21, [.control, .shift, .command]), (184, 23, [.shift, .command]),
            (32, 126, [.control]), (33, 125, [.control]), (79, 123, [.control]), (81, 124, [.control]),
            (60, 49, [.control]), (61, 49, [.control, .option]), (64, 49, [.command]), (65, 49, [.option, .command]),
            (98, 44, [.shift, .command]),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.0, SystemShortcut(id: $0.0, keyCode: $0.1, modifiers: $0.2)) })
    }()

    /// A readable name for well-known ids; nil for the others.
    static func name(of id: Int) -> String? {
        switch id {
        case 28, 29, 30, 31, 184:
            String(localized: "Screenshots", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut group a Cranny shortcut collides with")
        case 32: String(localized: "Mission Control", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 33: String(localized: "Application windows", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 79, 80, 81, 82: String(localized: "Move between spaces", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 60, 61: String(localized: "Switch input source", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 64: String(localized: "Spotlight", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 65: String(localized: "Finder search window", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        case 98: String(localized: "Help menu", bundle: .module, comment: "Settings ▸ Keyboard: macOS shortcut a Cranny shortcut collides with")
        default: nil
        }
    }
}
