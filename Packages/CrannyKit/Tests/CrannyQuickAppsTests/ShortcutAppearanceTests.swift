// How a shortcut tile looks without a user choice, and the contrast of every tile colour.
import AppKit
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func fnv1aMatchesTheReferenceVectors() {
    // Published FNV-1a 64-bit test vectors.
    #expect(ShortcutAppearance.fnv1a("") == 0xcbf2_9ce4_8422_2325)
    #expect(ShortcutAppearance.fnv1a("a") == 0xaf63_dc4c_8601_ec8c)
    #expect(ShortcutAppearance.fnv1a("foobar") == 0x8594_4171_f739_67e8)
}

@Test func automaticHueIsStableAndNeverGrey() {
    let names = ["Morning routine", "Отправить отчёт", "☀️", "", "Resize (50%) images"]
    for name in names {
        let tint = ShortcutAppearance.automaticTint(forName: name)
        #expect(tint == ShortcutAppearance.automaticTint(forName: name))
        #expect(tint != .gray)
    }
    // Pinned: a change of hash or palette would recolour every user's tiles.
    #expect(ShortcutAppearance.automaticTint(forName: "Morning routine") == ShortcutTint.automaticCases[
        Int(ShortcutAppearance.fnv1a("Morning routine") % UInt64(ShortcutTint.automaticCases.count))])
    // Canonically equivalent spellings (é precomposed or not) get the same colour.
    #expect(ShortcutAppearance.automaticTint(forName: "R\u{E9}sum\u{E9}") == ShortcutAppearance.automaticTint(forName: "Re\u{301}sume\u{301}"))
}

@Test func userChoiceWinsOverTheHash() {
    let entry = ShortcutEntry(id: "X", name: "Anything", tint: .gray)
    #expect(ShortcutAppearance.tint(for: entry) == .gray)
}

@Test func initialIsTheFirstLetterDigitOrEmoji() {
    #expect(ShortcutAppearance.initial(of: "morning") == "M")
    #expect(ShortcutAppearance.initial(of: "т-банк") == "Т")
    #expect(ShortcutAppearance.initial(of: "(Draft) Notes") == "D")
    #expect(ShortcutAppearance.initial(of: "  42 things") == "4")
    #expect(ShortcutAppearance.initial(of: "☀️ Morning") == "☀️")
    #expect(ShortcutAppearance.initial(of: "👩‍💻 Dev") == "👩‍💻")
    #expect(ShortcutAppearance.initial(of: "---") == nil)
    #expect(ShortcutAppearance.initial(of: "") == nil)
}

@Test func everyTintKeepsAWhiteGlyphAndTheTileReadable() {
    let card = CrannyPalette.make(.standard).spec.cardOverBlack
    for tint in ShortcutTint.allCases {
        #expect(RGB.white.contrast(with: tint.rgb) >= 3, "\(tint) glyph contrast")
        #expect(tint.rgb.contrast(with: card) >= 3, "\(tint) tile vs card")
    }
}

@Test func tintRawValuesAreStable() {
    #expect(ShortcutTint.allCases.map(\.rawValue) ==
            ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown", "gray"])
}

@Test func curatedSymbolsExistAndAreNotRestricted() throws {
    #expect(Set(ShortcutAppearance.symbols).count == ShortcutAppearance.symbols.count)
    for symbol in ShortcutAppearance.symbols + [ShortcutAppearance.fallbackSymbol, QuickAppsModule.symbol, "app.dashed", "checkmark.circle.fill",
                                                 "exclamationmark", "plus", "xmark", "sparkles", "arrow.triangle.2.circlepath"] {
        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
    }
    // Apple's restriction list (product-only symbols) on this Mac, when present.
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_restrictions.strings")
    if let restricted = NSDictionary(contentsOf: url) as? [String: String] {
        #expect(Set(ShortcutAppearance.symbols).isDisjoint(with: restricted.keys))
    }
}
