// CrannyQuickApps/Shortcuts/ShortcutAppearance.swift — how a shortcut tile looks without a user choice
// (DESIGN.md §7.3: "a stable hue hashed from its name … its SF Symbol glyph or first letter"). Pure, tested.
import Foundation

nonisolated enum ShortcutAppearance {
    /// The tile colour: the user's choice, else a hue hashed from the name. The hash is FNV-1a over the UTF-8
    /// bytes, so the colour is the same on every launch and every Mac (Swift's `Hasher` is seeded per process).
    static func tint(for entry: ShortcutEntry) -> ShortcutTint {
        entry.tint ?? automaticTint(forName: entry.name)
    }

    static func automaticTint(forName name: String) -> ShortcutTint {
        let hues = ShortcutTint.automaticCases
        return hues[Int(fnv1a(name.precomposedStringWithCanonicalMapping) % UInt64(hues.count))]
    }

    /// FNV-1a 64-bit.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The glyph of a tile without a symbol: the first letter, digit or emoji of the name, uppercased
    /// ("т-банк" → "Т", "☀️ Morning" → "☀️", "(Draft) Notes" → "D"); nil when the name has none.
    static func initial(of name: String) -> String? {
        for character in name {
            if character.isLetter || character.isNumber { return String(character).localizedUppercase }
            if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation })
                || (character.unicodeScalars.count > 1 && character.unicodeScalars.first?.properties.isEmoji == true) {
                return String(character)
            }
        }
        return nil
    }

    /// Glyphs offered in Settings ▸ Shortcuts. Content glyphs the user picks for their own shortcuts (not UI
    /// chrome): every one exists on macOS 14 and none is a restricted Apple product symbol (`ShortcutAppearanceTests`).
    static let symbols: [String] = [
        "bolt.fill", "star.fill", "heart.fill", "sparkles", "wand.and.stars", "lightbulb.fill",
        "house.fill", "briefcase.fill", "cart.fill", "creditcard.fill", "dollarsign.circle.fill", "chart.bar.fill",
        "envelope.fill", "phone.fill", "bubble.left.fill", "paperplane.fill", "link", "globe",
        "doc.text.fill", "folder.fill", "tray.full.fill", "list.bullet", "checklist", "calendar",
        "clock.fill", "alarm.fill", "timer", "sun.max.fill", "moon.fill", "cloud.fill",
        "music.note", "headphones", "photo.fill", "camera.fill", "mic.fill", "gamecontroller.fill",
        "book.fill", "graduationcap.fill", "car.fill", "airplane", "figure.walk", "leaf.fill",
        "flame.fill", "drop.fill", "hammer.fill", "wrench.and.screwdriver.fill", "terminal.fill", "keyboard",
        "display", "printer.fill", "lock.fill", "key.fill", "wifi", "power",
    ]

    /// The symbol shown when the name has no letter (and the neutral glyph under Demo-mode redaction).
    static let fallbackSymbol = "square.2.layers.3d.fill"
}
