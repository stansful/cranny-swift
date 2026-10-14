import AppKit
import Foundation
import Testing
@testable import CrannyCore

/// DESIGN.md §14.1: one list of symbols, each available on macOS 14, restricted ones only for their product.
@Suite("SF Symbols (DESIGN.md §14.1)") struct SymbolTests {
    private static let glyphs = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
    private static let hasCatalogue = FileManager.default.fileExists(
        atPath: glyphs.appending(path: "name_availability.plist").path)

    private static func plist(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: glyphs.appending(path: name))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @MainActor @Test func everySymbolResolves() {
        let missing = CrannySymbol.all.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "\(missing.sorted())")
    }

    /// The system's own catalogue: the release that introduced each name, and the restricted names.
    @Test(.enabled(if: hasCatalogue)) func everySymbolExistsOnMacOS14AndOnlyProductGlyphsAreRestricted() throws {
        let availability = try Self.plist("name_availability.plist")
        let introduced = try #require(availability["symbols"] as? [String: String])
        let releases = try #require(availability["year_to_release"] as? [String: [String: String]])
        for name in CrannySymbol.all.sorted() {
            let year = try #require(introduced[name], "\(name) is not an SF Symbol")
            let macOS = try #require(releases[year]?["macOS"], "\(name): no macOS release for \(year)")
            #expect(macOS.compare("14.0", options: .numeric) != .orderedDescending, "\(name) needs macOS \(macOS)")
        }
        let restricted = Set(try Self.plist("symbol_restrictions.strings").keys)
        #expect(CrannySymbol.all.intersection(restricted) == CrannySymbol.restrictedProductGlyphs)
        #expect(CrannySymbol.all.isSuperset(of: CrannySymbol.restrictedProductGlyphs))
    }

    /// `CrannySymbol` and the table in DESIGN.md §14.1 list the same names.
    @Test func listMatchesTheDesignTable() throws {
        let design = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/DESIGN.md")
        let text = try String(contentsOf: design, encoding: .utf8)
        let section = try #require(text.components(separatedBy: "### 14.1 SF Symbols").dropFirst().first)
        let table = try #require(section.components(separatedBy: "\n- ⚑").first)
        var names = Set<String>()
        for line in table.components(separatedBy: "\n") where line.hasPrefix("| ") && !line.hasPrefix("| Role") {
            let cells = line.components(separatedBy: "|")
            guard cells.count > 2 else { continue }
            for token in cells[2].components(separatedBy: "`").enumerated()
            where token.offset % 2 == 1 && token.element.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "." }) {
                names.insert(token.element)                 // a symbol name, not `NSWorkspace`
            }
        }
        names.remove("airdrop")                       // "there is no public `airdrop` symbol"
        #expect(names.count > 100)
        #expect(names.subtracting(CrannySymbol.all).isEmpty, "in §14.1, not in CrannySymbol: \(names.subtracting(CrannySymbol.all).sorted())")
        #expect(CrannySymbol.all.subtracting(names).isEmpty, "in CrannySymbol, not in §14.1: \(CrannySymbol.all.subtracting(names).sorted())")
    }
}
