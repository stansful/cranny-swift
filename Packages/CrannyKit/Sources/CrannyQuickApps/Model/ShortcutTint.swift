// CrannyQuickApps/Model/ShortcutTint.swift — the colours a shortcut tile can have (DESIGN.md §7.3).
import CrannyCore
import Foundation

/// The fill of a shortcut squircle. These are content colours (like a calendar's colour), not UI tokens: each
/// keeps a white 17-pt glyph at ≥ 3:1 and the squircle itself at ≥ 3:1 against a card (`ShortcutAppearanceTests`).
public nonisolated enum ShortcutTint: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    /// The sRGB fill.
    public var rgb: RGB {
        switch self {
        case .red: RGB(hex: 0xE5383B)
        case .orange: RGB(hex: 0xD9620B)
        case .yellow: RGB(hex: 0xB8860B)
        case .green: RGB(hex: 0x2E9E4F)
        case .mint: RGB(hex: 0x0F9488)
        case .teal: RGB(hex: 0x0E8BA8)
        case .blue: RGB(hex: 0x2F6FE4)
        case .indigo: RGB(hex: 0x5B4FE0)
        case .purple: RGB(hex: 0x8E4EC6)
        case .pink: RGB(hex: 0xD6336C)
        case .brown: RGB(hex: 0x9A6B47)
        case .gray: RGB(hex: 0x6E6E76)
        }
    }

    /// The hues an automatic tile is hashed onto (gray only when the user picks it).
    static let automaticCases: [ShortcutTint] = allCases.filter { $0 != .gray }

    /// Localized colour name (Settings ▸ Shortcuts colour picker, VoiceOver).
    var title: String {
        switch self {
        case .red: String(localized: "Red", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .orange: String(localized: "Orange", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .yellow: String(localized: "Yellow", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .green: String(localized: "Green", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .mint: String(localized: "Mint", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .teal: String(localized: "Teal", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .blue: String(localized: "Blue", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .indigo: String(localized: "Indigo", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .purple: String(localized: "Purple", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .pink: String(localized: "Pink", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .brown: String(localized: "Brown", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        case .gray: String(localized: "Gray", bundle: .module, comment: "Settings ▸ Shortcuts: tile colour name")
        }
    }
}
