import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

/// The band's words, resolved from the module's catalog in English and Russian, and measured in their text style
/// against the 48u medium slot (DESIGN.md §9.1: compact text only as abbreviations tested in both languages).
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

    @Test func meetingSoonStartsIn() throws {
        let en = try language("en"), ru = try language("ru")
        #expect(CalendarFormat.bandStartsIn(minutes: 4, language: en) == "in 4m")
        #expect(CalendarFormat.bandStartsIn(minutes: 4, language: ru) == "4 мин")          // no room for "через"
        // Every lead time (1–30 min) fits beside the camera in `compactLabel` (the dot drops first, by layout).
        for minutes in CalendarSettings.leadRange {
            for (code, lang) in [("en", en), ("ru", ru)] {
                let text = CalendarFormat.bandStartsIn(minutes: minutes, language: lang)
                #expect(width(text, .compactLabel) <= slot, "\(code) \(text)")
            }
        }
    }

    @Test func meetingSoonStartTimeFits() throws {
        for code in ["en", "ru"] {
            let lang = try language(code)
            for hour in [0, 9, 10, 12, 23] {
                let text = CalendarFormat.bandTime(T.date(h: hour, 59), language: lang)
                #expect(!text.contains("AM") && !text.contains("PM"), "\(code) \(text)")
                #expect(width(text, .compact) <= slot, "\(code) \(text)")
            }
        }
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

    @Test func meetingInProgressFitsTheSlot() throws {
        let en = try language("en"), ru = try language("ru")
        for minutes in durations {
            for text in [CalendarFormat.bandTimeLeft(minutes: minutes, language: en), CalendarFormat.bandTimeElapsed(minutes: minutes, language: en)] {
                #expect(width(text, .compact) <= slot, "en \(text)")                   // English never shrinks
            }
            for text in [CalendarFormat.bandTimeLeft(minutes: minutes, language: ru), CalendarFormat.bandTimeElapsed(minutes: minutes, language: ru)] {
                let full = width(text, .compact)
                #expect(full * CalendarFormat.bandMinimumScale <= slot, "ru \(text): \(full) pt")
                if minutes >= 60 { #expect(full <= slot, "ru \(text)") }             // "−1:30" never shrinks
            }
        }
        // Why the band does not say "12m left" (DESIGN.md §9.2): it is wider than the slot even in English.
        #expect(width(phraseLeft(12, en), .compact) > slot)
        #expect(width(phraseLeft(12, ru), .compact) > slot)
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
