import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

/// DESIGN.md §7.2: the widget's header line never cuts the weekday or the day number short ("W…" beside "+2 more" and
/// ‹ › was the finding, in English at 3 cells). `DayHeader` offers its `DayHeaderLine`s to `ViewThatFits`, which shows
/// the first whose ideal width fits beside ‹ ›; these tests measure each line in every language of the module's
/// catalog, on each day of a week, and check that one fits at every density and text size.
@Suite @MainActor struct DayHeaderFitTests {
    /// Thursday 22 to Wednesday 28 October 2026: every weekday, with a two-digit day.
    private let week: [Date] = (22...28).map {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: $0, hour: 12))!
    }
    /// ‹ › (`DayPager`: two 28-pt buttons) and the stack's spacing before it.
    private let pager = 2 * HitTarget.preferred + Space.xs

    /// What `ViewThatFits` compares with the room: the line's ideal width, with "+9 more" when the line has a count.
    private func idealWidth(_ line: DayHeaderLine, date: Date, code: String, textSize: CrannyTextSize) -> CGFloat {
        var theme = CrannyTheme()
        theme.textSize = textSize
        let dates = DayHeaderLine.Dates(date, locale: Locale(identifier: code))
        let body = DayHeaderLineBody(line: line, date: date, dates: dates, isToday: true, more: 9)
        return NSHostingView(rootView: body.fixedSize().crannyThemeRoot(theme).environment(\.locale, Locale(identifier: code)))
            .fittingSize.width
    }

    /// The room beside ‹ ›: the card's content width at 3 cells, or the second of two columns at 5 (`CalendarWidgetView`:
    /// `Space.m`, a 1-pt hairline, `Space.m`).
    private func room(cells: Int, grid: NookGrid) -> CGFloat {
        let content = grid.width(cells: cells) - 2 * grid.density.cardPadding
        return (cells >= 5 ? (content - 2 * Space.m - 1) / 2 : content) - pager
    }

    private func pick(_ ideal: [CGFloat], room: CGFloat) -> DayHeaderLine {
        DayHeaderLine.allCases.indices.first { ideal[$0] <= room }.map { DayHeaderLine.allCases[$0] } ?? .shortWeekday
    }

    /// One case per language; its failures are collected into one issue with the measured ideal widths.
    @Test(arguments: bandLanguages) func weekdayAndDayAlwaysFit(code: String) {
        var failures: [String] = []
        for textSize in CrannyTextSize.allCases {
            for date in week {
                let ideal = DayHeaderLine.allCases.map { idealWidth($0, date: date, code: code, textSize: textSize) }
                for density in NookDensity.allCases {
                    let grid = NookGrid(density: density, textSize: textSize)
                    for cells in [3, 5] where ideal.last! > room(cells: cells, grid: grid) {
                        let day = CalendarFormat.weekday(date, locale: Locale(identifier: code))
                        failures.append("\(textSize) \(density) \(cells) cells (\(room(cells: cells, grid: grid)) pt), \(day): \(ideal)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(code): \(failures.count) header line(s) do not fit: \(failures.joined(separator: "; "))")
    }

    /// Where the room goes, in English: the date shortens first, then "+N more" (→ "+N" → gone).
    @Test func englishGivesUpTheMonthThenTheWord() {
        let wednesday = week[6]
        let ideal = DayHeaderLine.allCases.map { idealWidth($0, date: wednesday, code: "en", textSize: .standard) }
        let standard = NookGrid(density: .standard, textSize: .standard), roomy = NookGrid(density: .roomy, textSize: .standard)
        #expect(pick(ideal, room: room(cells: 3, grid: roomy)) == .dayOnly)          // "WED 28   +9 more ‹ ›"
        #expect(pick(ideal, room: room(cells: 3, grid: standard)) == .countOnly)     // "WED 28   +9 ‹ ›"
        #expect(pick(ideal, room: room(cells: 5, grid: standard)) == .noMore)        // "WED 28 ‹ ›"
        #expect(pick(ideal, room: .infinity) == .full)
    }

    /// The model above, checked against `ViewThatFits` itself (`DayHeaderChoice`), beside a stand-in for ‹ ›.
    @Test func viewThatFitsPicksAsMeasured() async throws {
        let cases: [(code: String, width: CGFloat, expected: DayHeaderLine)] = [
            ("en", 160, .countOnly), ("en", 188, .dayOnly), ("en", 135.5, .noMore), ("pt-PT", 123.5, .shortWeekday),
        ]
        for c in cases {
            let box = HeaderPickBox()
            let header = HStack(spacing: Space.xs) {
                DayHeaderChoice { line in
                    DayHeaderLineBody(line: line, date: week[6], dates: DayHeaderLine.Dates(week[6], locale: Locale(identifier: c.code)),
                                      isToday: true, more: 9)
                        .onAppear { box.shown.append(line) }
                }
                Color.clear.frame(width: 2 * HitTarget.preferred, height: 16)
            }
            let host = NSHostingView(rootView: header.frame(width: c.width, height: 16).crannyThemeRoot(CrannyTheme())
                .environment(\.locale, Locale(identifier: c.code)))
            host.frame = CGRect(x: 0, y: 0, width: c.width, height: 16)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await settle(1)
            }
            #expect(box.shown.last == c.expected, "\(c.code) at \(c.width) pt: \(box.shown)")
            window.contentView = nil
        }
    }

    /// "+3" still says "+3 more" to VoiceOver, in the locale's digits.
    @Test func theCountUsesTheLocaleDigits() {
        #expect(3.formatted(.number.sign(strategy: .always()).locale(Locale(identifier: "en"))) == "+3")
        #expect(3.formatted(.number.sign(strategy: .always()).locale(Locale(identifier: "ar-SA"))).contains("٣"))
    }
}

/// The lines `ViewThatFits` put on screen, in order.
@MainActor private final class HeaderPickBox {
    var shown: [DayHeaderLine] = []
}
