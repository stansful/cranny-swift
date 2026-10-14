// `shortcuts list --show-identifiers` parsing. The fixture follows the format captured on macOS 27.0.1
// (`Name (UUID)`, one per line, uppercase UUIDs); the names are synthetic so no user's shortcuts end up in the repo.
import Foundation
import Testing
@testable import CrannyQuickApps

/// Output shaped like the real capture, with the hard cases: parentheses inside and at the end of a name,
/// Cyrillic, emoji (incl. a ZWJ sequence and a flag), a name that is only parentheses, trailing spaces.
let shortcutListFixture = """
    Morning routine (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)
    Resize (50%) images (5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02)
    Отправить отчёт (9E3F7A21-0C4D-4B8E-A5F6-1D2C3B4A5E03)
    Т-Инвестиции (2A4B6C8D-1E3F-4A5B-8C7D-9E0F1A2B3C04)
    Clean Desktop 🧹 (7F6E5D4C-3B2A-4190-8F7E-6D5C4B3A2905)
    👩‍💻 Dev mode 🇷🇺 (11111111-2222-4333-8444-555555555506)
    Backup (weekly) (AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEE07)
    (draft) (BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFF08)
    Trailing spaces    (CCCCCCCC-DDDD-4EEE-8FFF-00000000000A)

    """

@Test func parsesEveryLineOfTheCapturedFormat() {
    let list = ShortcutListParser.parse(shortcutListFixture)
    #expect(list.map(\.name) == [
        "Morning routine", "Resize (50%) images", "Отправить отчёт", "Т-Инвестиции", "Clean Desktop 🧹",
        "👩‍💻 Dev mode 🇷🇺", "Backup (weekly)", "(draft)", "Trailing spaces",
    ])
    #expect(list.first?.id == "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01")
    #expect(list.allSatisfy { UUID(uuidString: $0.id) != nil })
}

@Test func parsesBytesAsUTF8() {
    let list = ShortcutListParser.parse(Data(shortcutListFixture.utf8))
    #expect(list.count == 9)
    #expect(list[2].name == "Отправить отчёт")
}

@Test func identifierIsTheLastParenthesisedGroup() throws {
    let info = try #require(ShortcutListParser.parseLine("A (b) (c) (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)"))
    #expect(info.name == "A (b) (c)")
    #expect(info.id == "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01")
}

@Test func lowercaseIdentifiersAreNormalised() {
    #expect(ShortcutListParser.parseLine("x (0d7a5b52-6a0e-4c38-9c1f-3e2f1b6d9a01)")?.id == "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01")
}

@Test func linesWithoutAnIdentifierAreSkipped() {
    let output = """
        Plain name without identifier
        Ends in parentheses (not a uuid)
        Broken (0D7A5B52-6A0E-4C38-9C1F
        (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01) leading id only
        Good one (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)
        """
    #expect(ShortcutListParser.parse(output).map(\.name) == ["Good one"])
}

@Test func windowsLineEndingsBOMAndBlankLines() {
    let output = "\u{FEFF}First (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)\r\n\r\nSecond (5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02)\r\n"
    #expect(ShortcutListParser.parse(output).map(\.name) == ["First", "Second"])
}

@Test func repeatedIdentifierKeepsTheFirstLine() {
    let output = "One (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)\nTwo (0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)"
    #expect(ShortcutListParser.parse(output).map(\.name) == ["One"])
}

@Test func emptyNameIsKeptAndShownAsUntitled() throws {
    let info = try #require(ShortcutListParser.parseLine("(0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01)"))
    #expect(info.name.isEmpty)
    #expect(!ShortcutEntry(id: info.id, name: info.name).displayName.isEmpty)
}

@Test func emptyOutputIsAnEmptyList() {
    #expect(ShortcutListParser.parse("").isEmpty)
    #expect(ShortcutListParser.parse("\n\n").isEmpty)
}
