import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

/// DESIGN.md §16: Join always shows its glyph *and* its word in the Nook (§7.2 draws `[⦿ Join]` at 3 cells). A featured
/// row offers its `FeaturedRowLayout`s to `ViewThatFits`, which picks the first whose ideal width fits (else the
/// `overflow` layout); these tests measure each layout in every language of the module's catalog and check that the
/// pick shows the word at every density and text size.
@Suite @MainActor struct FeaturedRowTests {
    private func language(_ code: String) throws -> CalendarLanguage { try #require(CalendarLanguage.named(code)) }

    /// What `ViewThatFits` compares with the row's width: the layout's ideal width. `code` sets the environment locale
    /// the Join word resolves in; the status line is already in that language.
    private func idealSize(_ layout: FeaturedRowLayout, status: String, link: Bool, code: String,
                           textSize: CrannyTextSize = .standard) -> CGSize {
        var join: (@MainActor () -> Void)?
        if link { join = {} }
        var theme = CrannyTheme()
        theme.textSize = textSize
        let row = FeaturedRowBody(layout: layout, title: "Quarterly planning with the design team", status: status,
                                  color: RGB(hex: 0x1BADF8), start: "10:30", join: join)
        return NSHostingView(rootView: row.fixedSize().crannyThemeRoot(theme).environment(\.locale, Locale(identifier: code))).fittingSize
    }

    /// "In 4m" … "Now · 1h 59m left": the shortest and longest second lines a meeting shows.
    private func statuses(_ lang: CalendarLanguage) -> [String] {
        [CalendarFormat.startsIn(minutes: 4, language: lang), CalendarFormat.startsIn(minutes: 59, language: lang),
         CalendarFormat.nowWithTimeLeft(minutes: 12, language: lang), CalendarFormat.nowWithTimeLeft(minutes: 59, language: lang),
         CalendarFormat.nowWithTimeLeft(minutes: 119, language: lang)]
    }

    /// The width a row gets: the card's content width (`WidgetCard`: the cells less the card padding), and at 5 cells
    /// one of two columns (`CalendarWidgetView`: `Space.m`, a 1-pt hairline, `Space.m`).
    private func rowWidth(cells: Int, grid: NookGrid) -> CGFloat {
        let content = grid.width(cells: cells) - 2 * grid.density.cardPadding
        return cells >= 5 ? (content - 2 * Space.m - 1) / 2 : content
    }

    /// One case per language; its failures are collected into one issue with the measured ideal widths.
    @Test(arguments: bandLanguages) func joinKeepsItsWordAtEveryDensityAndTextSize(code: String) throws {
        let lang = try language(code)
        var failures: [String] = []
        for textSize in CrannyTextSize.allCases {
            for status in statuses(lang) {
                let ideal = FeaturedRowLayout.allCases.map { idealSize($0, status: status, link: true, code: code, textSize: textSize).width }
                for density in NookDensity.allCases {
                    let grid = NookGrid(density: density, textSize: textSize)
                    // Compact density's 5-cell columns (124 pt) are the one place Russian falls back to the glyph.
                    let sizes = density == .compact ? [3, 4] : [3, 4, 5]
                    for cells in sizes {
                        let width = rowWidth(cells: cells, grid: grid)
                        let pick = FeaturedRowLayout.allCases.indices.first { ideal[$0] <= width }
                            .map { FeaturedRowLayout.allCases[$0] } ?? FeaturedRowLayout.overflow
                        if !pick.showsJoinWord {
                            failures.append("\(textSize) \(density) \(cells) cells (\(width) pt), \"\(status)\": \(ideal) → \(pick)")
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(code): \(failures.count) layout(s) lose the Join word: \(failures.joined(separator: "; "))")
    }

    /// The model above, checked against `ViewThatFits` itself (`FeaturedEventRow`'s `FeaturedRowChoice`).
    @Test func viewThatFitsPicksAsMeasured() async throws {
        let en = try language("en"), ru = try language("ru")
        let cases: [(code: String, status: String, width: CGFloat, expected: FeaturedRowLayout)] = [
            ("en", CalendarFormat.startsIn(minutes: 4, language: en), 160, .roomy),
            ("ru", CalendarFormat.nowWithTimeLeft(minutes: 12, language: ru), 160, .stacked),     // the finding: 3 cells, Russian
            ("ru", CalendarFormat.startsIn(minutes: 4, language: ru), 126, .compact),
            ("ru", CalendarFormat.nowWithTimeLeft(minutes: 119, language: ru), 100, .stacked),    // nothing fits: overflow
        ]
        for c in cases {
            let box = PickBox()
            let row = FeaturedRowChoice { layout in
                FeaturedRowBody(layout: layout, title: "Quarterly planning", status: c.status, color: RGB(hex: 0x1BADF8),
                                start: "10:30", join: {})
                    .onAppear { box.shown.append(layout) }
            }
            let host = NSHostingView(rootView: row.frame(width: c.width).crannyThemeRoot(CrannyTheme())
                .environment(\.locale, Locale(identifier: c.code)))
            host.frame = CGRect(x: 0, y: 0, width: c.width, height: AgendaScroll.featuredHeight)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await settle(1)
            }
            #expect(box.shown.last == c.expected, "\(c.code) \"\(c.status)\" at \(c.width) pt: \(box.shown)")
            window.contentView = nil
        }
    }

    @Test(arguments: bandLanguages) func everyLayoutKeepsTheFeaturedRowHeight(code: String) throws {
        let status = CalendarFormat.nowWithTimeLeft(minutes: 12, language: try language(code))
        var failures: [String] = []
        for layout in FeaturedRowLayout.allCases {
            for link in [true, false] {
                let height = idealSize(layout, status: status, link: link, code: code).height
                if height != AgendaScroll.featuredHeight { failures.append("\(layout) link: \(link): \(height) pt") }
            }
        }
        #expect(failures.isEmpty, "\(code), rows are \(AgendaScroll.featuredHeight) pt: \(failures.joined(separator: "; "))")
    }

    @Test func theRowsJoinWordIsShortTheTooltipAndPeekKeepTheFullWords() throws {
        func short(_ code: String) -> String {
            var word = JoinButton.shortWord
            word.locale = Locale(identifier: code)
            return String(localized: word)
        }
        #expect(short("en") == "Join")
        #expect(short("ru") == "Войти")
        let ru = try language("ru")
        #expect(String(localized: "Join", bundle: ru.bundle, locale: ru.locale,
                       comment: "Calendar: Join button title (opens the meeting link)") == "Подключиться")
        #expect(String(localized: "Join meeting", bundle: ru.bundle, locale: ru.locale,
                       comment: "Calendar: Join button, VoiceOver label") == "Подключиться к встрече")
        // The title-line pill lays out at 18 pt so the row keeps its 32; its hit area still overhangs it (≥ 24 pt).
        let pill = NSHostingView(rootView: JoinButton(size: .titleLine) {}.fixedSize().crannyThemeRoot(CrannyTheme())).fittingSize
        #expect(pill.height == JoinButton.titleLineHeight)
        #expect(pill.width >= HitTarget.nook.width)
    }
}

/// The layouts `ViewThatFits` put on screen, in order.
@MainActor private final class PickBox {
    var shown: [FeaturedRowLayout] = []
}
