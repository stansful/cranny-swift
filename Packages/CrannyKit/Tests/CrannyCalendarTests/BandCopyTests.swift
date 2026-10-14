import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

/// Every language the module's catalog is compiled into (new languages are measured as soon as they are merged);
/// the featured-row tests use it too.
nonisolated let bandLanguages: [String] = Bundle.module.localizations.filter { $0 != "Base" }.sorted()

/// The band's words, resolved from the module's catalog in every language, and measured in their text style
/// against the 48u medium slot (DESIGN.md §9.1: compact text only as abbreviations tested in every language).
@Suite @MainActor struct BandCopyTests {
    /// The content width of a medium slot at notch unit 1: 68 − 12 (outer) − 8 (camera gap), as `CompactSlots`.
    private let slot = SlotWidth.medium.points(unit: 1) - 12 - 8
    /// Up to 11 h 59 min: longer events are not meetings (`EventSnapshot.isMeetingLike`).
    private let durations = [1, 4, 9, 10, 12, 30, 59, 60, 61, 90, 150, 599, 600, 719]

    private func language(_ code: String) throws -> CalendarLanguage { try #require(CalendarLanguage.named(code)) }

    /// The width SwiftUI lays the text out at, unconstrained.
    private func width(_ text: String, _ style: CrannyTextStyle) -> CGFloat {
        NSHostingView(rootView: Text(verbatim: text).crannyFont(style).fixedSize().crannyThemeRoot(CrannyTheme())).fittingSize.width
    }

    @Test func slotIsTheMediumContentWidth() {
        #expect(slot == 48)
    }

    @Test func everyCatalogLanguageIsMeasured() {
        #expect(bandLanguages.contains("en") && bandLanguages.contains("ru"), "\(bandLanguages)")
    }

    @Test func meetingSoonStartsIn() throws {
        let en = try language("en"), ru = try language("ru")
        #expect(CalendarFormat.bandStartsIn(minutes: 4, language: en) == "in 4m")
        #expect(CalendarFormat.bandStartsIn(minutes: 4, language: ru) == "4 мин")          // no room for "через"
    }

    /// Every lead time (1–30 min) fits beside the camera in `compactLabel` (the dot drops first, by layout).
    @Test(arguments: bandLanguages) func meetingSoonStartsInFits(code: String) throws {
        let lang = try language(code)
        let failures = CalendarSettings.leadRange.compactMap { minutes -> String? in
            let text = CalendarFormat.bandStartsIn(minutes: minutes, language: lang)
            let measured = width(text, .compactLabel)
            return measured <= slot ? nil : "«\(text)» \(measured) pt"
        }
        #expect(failures.isEmpty, "\(code), \(slot)-pt slot: \(failures.joined(separator: "; "))")
    }

    @Test(arguments: bandLanguages) func meetingSoonStartTimeFits(code: String) throws {
        let lang = try language(code)
        var failures: [String] = []
        for hour in [0, 9, 10, 12, 23] {
            let text = CalendarFormat.bandTime(T.date(h: hour, 59), language: lang)
            if text.contains("AM") || text.contains("PM") { failures.append("«\(text)» has AM/PM") }
            let measured = width(text, .compact)
            if measured > slot { failures.append("«\(text)» \(measured) pt") }
        }
        #expect(failures.isEmpty, "\(code), \(slot)-pt slot: \(failures.joined(separator: "; "))")
    }

    @Test func meetingInProgressForms() throws {
        let en = try language("en"), ru = try language("ru")
        #expect(CalendarFormat.bandTimeLeft(minutes: 12, language: en) == "−12m")
        #expect(CalendarFormat.bandTimeElapsed(minutes: 12, language: en) == "+12m")
        #expect(CalendarFormat.bandTimeLeft(minutes: 90, language: en) == "−1:30")
        #expect(CalendarFormat.bandTimeLeft(minutes: 12, language: ru) == "−12 мин")
        #expect(CalendarFormat.bandTimeElapsed(minutes: 12, language: ru) == "+12 мин")
        #expect(CalendarFormat.bandTimeElapsed(minutes: 150, language: ru) == "+2:30")
        // The two settings never look alike, in either language, for any duration.
        for minutes in durations {
            for lang in [en, ru] {
                #expect(CalendarFormat.bandTimeLeft(minutes: minutes, language: lang) != CalendarFormat.bandTimeElapsed(minutes: minutes, language: lang))
            }
        }
    }

    /// English never shrinks; other languages may shrink to `bandMinimumScale` below an hour ("−59 мин"); "−1:30"
    /// never shrinks.
    @Test(arguments: bandLanguages) func meetingInProgressFitsTheSlot(code: String) throws {
        let lang = try language(code)
        var failures: [String] = []
        for minutes in durations {
            for text in [CalendarFormat.bandTimeLeft(minutes: minutes, language: lang),
                         CalendarFormat.bandTimeElapsed(minutes: minutes, language: lang)] {
                let full = width(text, .compact)
                let mayShrink = code != "en" && minutes < 60
                let drawn = mayShrink ? full * CalendarFormat.bandMinimumScale : full
                if drawn > slot {
                    failures.append("«\(text)» \(full) pt" + (mayShrink ? " (× \(CalendarFormat.bandMinimumScale) = \(drawn))" : ""))
                }
            }
        }
        #expect(failures.isEmpty, "\(code), \(slot)-pt slot: \(failures.joined(separator: "; "))")
    }

    /// Why the band does not say "12m left" (DESIGN.md §9.2): it is wider than the slot even in English.
    @Test func theFullPhraseDoesNotFitTheSlot() throws {
        #expect(width(phraseLeft(12, try language("en")), .compact) > slot)
        #expect(width(phraseLeft(12, try language("ru")), .compact) > slot)
    }

    /// The peek's and VoiceOver's "12m left" / "ещё 12 мин", from the catalog.
    private func phraseLeft(_ minutes: Int, _ lang: CalendarLanguage) -> String {
        let d = CalendarFormat.duration(minutes: minutes, language: lang)
        return String(localized: "\(d) left", bundle: lang.bundle, locale: lang.locale,
                      comment: "Meeting in progress: time left; the argument is a duration (\"12m left\", VoiceOver \"12 minutes left\")")
    }

    @Test func fullPhrasesStayInThePeekAndVoiceOver() throws {
        #expect(phraseLeft(12, try language("en")) == "12m left")
        #expect(phraseLeft(12, try language("ru")) == "ещё 12 мин")
    }
}
