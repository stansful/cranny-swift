// ⌘K: tiles as commands with ⌥1–⌥9, the rest of Shortcuts.app once the user types, ranking.
import CrannyCore
import Foundation
import Testing
@testable import CrannyQuickApps

@Test func matcherRanksPrefixThenWordThenAnywhere() {
    #expect(CommandMatcher.score(["Safari"], query: "saf") == 2)
    #expect(CommandMatcher.score(["Morning routine"], query: "rout") == 1)
    #expect(CommandMatcher.score(["Morning routine"], query: "outi") == 0)
    #expect(CommandMatcher.score(["Morning routine"], query: "xyz") == nil)
    #expect(CommandMatcher.score(["Résumé"], query: "resume") == 2)          // diacritics ignored
    #expect(CommandMatcher.score(["Отправить отчёт"], query: "отчет") == 1)   // ё = е
    #expect(CommandMatcher.score(["Anything"], query: "  ") == 0)
    #expect(CommandMatcher.score(["a", "Safari"], query: "saf") == 2)       // best of several texts
}

@Test func aTrimmedQueryScoresLikeTheRawOne() {
    for query in ["  saf ", "rout\n", "  ", "xyz"] {
        for texts in [["Safari"], ["Morning routine"], ["a", "Safari"]] {
            #expect(CommandMatcher.score(texts, trimmedQuery: CommandMatcher.trimmed(query)) == CommandMatcher.score(texts, query: query))
        }
    }
}

@Test func optionDigitKeyCombos() throws {
    let first = try #require(CommandMatcher.optionDigit(0))
    #expect(first.keyCode == 18 && first.modifiers == [.option] && first.display == "⌥1")
    #expect(CommandMatcher.optionDigit(4)?.keyCode == 23)                     // kVK_ANSI_5 is not 22
    #expect(CommandMatcher.optionDigit(8)?.display == "⌥9")
    #expect(CommandMatcher.optionDigit(9) == nil)
    #expect(CommandMatcher.optionDigit(-1) == nil)
}

@Test func emptyQueryListsTheTilesWithTheirKeys() async {
    let morning = ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine")
    let h = ModelHarness(installed: ["com.apple.Safari", "com.apple.mail"], apps: ["com.apple.Safari", "com.apple.mail"],
                         shortcuts: [morning], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    await h.model.shortcutsCatalog.refresh()
    let commands = QuickAppsCommands(model: h.model).commands(matching: "")
    #expect(commands.map(\.id.rawValue) == ["quickapps.open.com.apple.Safari", "quickapps.open.com.apple.mail", "quickapps.run.\(morning.id)"])
    #expect(commands.map { $0.shortcut?.display } == ["⌥1", "⌥2", "⌥3"])
    #expect(commands[2].kind != commands[0].kind)
    h.model.stop()
}

@Test func typingAlsoFindsShortcutsNotOnTheLauncher() async {
    let h = ModelHarness(installed: ["com.apple.Safari"], apps: ["com.apple.Safari"], cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    await h.model.shortcutsCatalog.refresh()
    let results = QuickAppsCommands(model: h.model).commands(matching: "отч")
    #expect(results.map(\.id.rawValue) == ["quickapps.run.9E3F7A21-0C4D-4B8E-A5F6-1D2C3B4A5E03"])
    #expect(results.first?.shortcut == nil)
    // Prefix matches rank first.
    let ranked = QuickAppsCommands(model: h.model).commands(matching: "re")
    #expect(ranked.first?.id.rawValue == "quickapps.run.5C1B1E0B-2B7A-4E59-8D3B-7A0C1F3E2D02")   // "Resize (50%) images"
    h.model.stop()
}

@Test func listedShortcutsMatchTheirShownName() async {
    // The list's display names are worked out once per read: an unnamed shortcut answers "Untitled shortcut", and a
    // padded query still finds a shortcut.
    let listing = "   (7B2C4D6E-8F01-4A23-B456-C789D0E1F2A3)\nSend weekly report (6A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9)\n"
    let h = ModelHarness(cli: FakeCLI(listing: listing))
    await h.model.start()
    await h.model.shortcutsCatalog.refresh()
    let untitled = ShortcutEntry(id: "7B2C4D6E-8F01-4A23-B456-C789D0E1F2A3", name: "").displayName
    let commands = QuickAppsCommands(model: h.model)
    #expect(commands.commands(matching: untitled).map(\.id.rawValue) == ["quickapps.run.7B2C4D6E-8F01-4A23-B456-C789D0E1F2A3"])
    #expect(commands.commands(matching: "  weekly ").map(\.id.rawValue) == ["quickapps.run.6A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9"])
    h.model.stop()
}

@Test func appCommandsMatchTheBundleIdentifierToo() async {
    let h = ModelHarness(installed: ["com.apple.Safari"], apps: ["com.apple.Safari"])
    await h.model.start()
    #expect(QuickAppsCommands(model: h.model).commands(matching: "com.apple").count == 1)
    h.model.stop()
}

@Test func performingCommandsLaunchesAndRuns() async {
    let morning = ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine")
    let fake = FakeCLI()
    let h = ModelHarness(installed: ["com.apple.Safari"], apps: ["com.apple.Safari"], shortcuts: [morning], cli: fake)
    await h.model.start()
    let commands = QuickAppsCommands(model: h.model).commands(matching: "")
    commands[0].perform()
    commands[1].perform()
    #expect(await waitUntil { h.launcher.opened.count == 1 && fake.calls == [["run", morning.id]] })
    h.model.stop()
}

@Test func demoModeHidesShortcutNamesInThePalette() async {
    let morning = ShortcutEntry(id: "0D7A5B52-6A0E-4C38-9C1F-3E2F1B6D9A01", name: "Morning routine", symbol: "sun.max.fill")
    let h = ModelHarness(installed: ["com.apple.Safari"], apps: ["com.apple.Safari"], shortcuts: [morning],
                         cli: FakeCLI(listing: shortcutListFixture))
    await h.model.start()
    await h.model.shortcutsCatalog.refresh()
    h.environment.isDemoMode = true
    let commands = QuickAppsCommands(model: h.model)
    let all = commands.commands(matching: "")
    #expect(all.map(\.title).last?.contains("Morning") == false)          // "Run Shortcut", still with its ⌥ key
    #expect(all.last?.shortcut?.display == "⌥2")
    #expect(all.last?.symbol == ShortcutAppearance.fallbackSymbol)
    #expect(commands.commands(matching: "отч").isEmpty)                   // the rest of Shortcuts.app is not listed
    #expect(commands.commands(matching: "morn").count == 1)               // the tile still answers its own name
    h.model.stop()
}
