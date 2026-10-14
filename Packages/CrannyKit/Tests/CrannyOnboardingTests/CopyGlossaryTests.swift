// The onboarding's copy names things the way the rest of Cranny does (ARCHITECTURE.md §8.7: one glossary across
// the catalogs). Checked on the compiled Russian table, so every key counts, including ones added later.
import Foundation
import Testing
@testable import CrannyOnboarding

@Suite struct CopyGlossaryTests {
    /// The compiled Russian strings of this module: key → value.
    private func russian() throws -> [String: String] {
        let bundle = try #require(Bundle.onboardingStrings("ru"))
        let path = try #require(bundle.path(forResource: "Localizable", ofType: "strings"))
        return try #require(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    /// ⌘K search words may list synonyms ("tour", «тур»); they are never shown as copy.
    private static let searchWords = "tutorial, tour, stop, end, skip"

    @Test func theTutorialIsCalledTheTutorialEverywhere() throws {
        // The menu bar says "Show Tutorial" / «Показать обучение» and Settings ▸ About "Replay Tutorial" /
        // «Пройти обучение снова»: the bubble, the Welcome window and the farewell use the same word, so "replay
        // it from the menu bar" leads to an item with that name.
        let table = try russian()
        let named = table.filter { $0.key != Self.searchWords && $0.key.range(of: "tutorial", options: .caseInsensitive) != nil }
        #expect(named.count >= 4)                                  // Skip, the Welcome button, both endings
        for (key, value) in named {
            #expect(value.range(of: "обучени", options: .caseInsensitive) != nil, "\(key) → \(value)")
        }
        for (key, value) in table where key != Self.searchWords {
            #expect(key.range(of: "tour", options: .caseInsensitive) == nil, "\(key)")
            #expect(value.range(of: #"(^|[^а-яё])тур"#, options: [.regularExpression, .caseInsensitive]) == nil, "\(key) → \(value)")
        }
    }

    @Test func aClickIsNazhatAsInApplesRussian() throws {
        // macOS's own Russian says «Нажмите, чтобы…» for a click; Cranny's other catalogs do too (Quick Apps, To-dos,
        // Notes). «Щёлкнуть» / «щелчок» would name the same act two ways, sometimes in one flow.
        let table = try russian()
        let clicks = table.filter { $0.key.range(of: "click", options: .caseInsensitive) != nil }
        #expect(clicks.count >= 6)                                 // the Click card, the coach marks, step 1, VoiceOver
        for (key, value) in clicks {
            #expect(value.range(of: "нажм|нажат", options: [.regularExpression, .caseInsensitive]) != nil, "\(key) → \(value)")
        }
        for (key, value) in table {
            #expect(value.range(of: "щ[её]лк|щ[её]лч", options: [.regularExpression, .caseInsensitive]) == nil, "\(key) → \(value)")
        }
    }

    @Test func theAutomationFallbackReasonNamesNoPlayer() throws {
        // The Automation row stands for every player a module declared (§10.20 #28): its fallback reason names none,
        // in either language (Media's own reason, shown first, names none either).
        let english = "Control playback in your media apps when other ways fail. Cranny sends only playback commands."
        let russianValue = try #require(try russian()[english])
        #expect([english, russianValue].contains(PermissionGroup.automation.fallbackReason))   // the test runs in either
        for text in [english, russianValue] {
            for player in ["Music", "Музык", "Spotify"] {
                #expect(text.range(of: player, options: .caseInsensitive) == nil, "\(text)")
            }
        }
        // Media's Russian word for a media app is «плеер» («Открыть плеер», «Не видит плеер»).
        #expect(russianValue.contains("плеерах") && !russianValue.contains("медиаприлож"), "\(russianValue)")
    }
}
