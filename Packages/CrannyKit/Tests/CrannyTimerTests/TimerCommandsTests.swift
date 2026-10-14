import CrannyCore
import Foundation
import Testing
@testable import CrannyTimer

@Suite struct TimerCommandCatalogTests {
    let presets = [60, 300, 600, 1500]
    let keywords = ["Timer", "Countdown"]

    /// English titles, so the matching rules are tested independently of the machine's language.
    func title(_ entry: TimerCommandEntry) -> String {
        switch entry {
        case .start(let s): s % 60 == 0 ? "Start \(s / 60)-minute timer" : "Start timer for \(s) s"
        case .pause: "Pause timer"
        case .resume: "Resume timer"
        case .addMinute: "Add 1 minute"
        case .stop: "Stop timer"
        }
    }

    func entries(_ query: String, _ state: TimerState = TimerState()) -> [TimerCommandEntry] {
        TimerCommandCatalog.entries(state: state, presets: presets, query: query, title: title, keywords: keywords)
    }

    @Test func emptyQueryListsThePresetsWhenIdle() {
        #expect(entries("") == presets.map { .start(seconds: $0) })
    }

    @Test func controlsOfTheCurrentTimerComeFirst() {
        let running = TimerState(phase: .running(endDate: t0), total: 300)
        #expect(Array(entries("", running).prefix(3)) == [.pause, .addMinute, .stop])
        let paused = TimerState(phase: .paused(remaining: 3), total: 300)
        #expect(Array(entries("", paused).prefix(3)) == [.resume, .addMinute, .stop])
        let done = TimerState(phase: .done(at: t0), total: 300)
        #expect(Array(entries("", done).prefix(2)) == [.stop, .addMinute])
    }

    @Test func aTypedDurationOffersExactlyThatTimer() {
        #expect(entries("12") == [.start(seconds: 720)])
        #expect(entries("timer 90s") == [.start(seconds: 90)])
        #expect(entries("start 1:30") == [.start(seconds: 90)])
        #expect(entries("countdown 25") == [.start(seconds: 1500)])
        #expect(entries("pizza 12").isEmpty)                                     // the other words must match
    }

    @Test func aUnitAfterASpaceBelongsToItsNumber() {
        #expect(entries("90 s") == [.start(seconds: 90)])
        #expect(entries("timer 90 s") == [.start(seconds: 90)])
        #expect(entries("90 sec") == [.start(seconds: 90)])
        #expect(entries("1 hour") == [.start(seconds: 3600)])
        #expect(entries("2 h") == [.start(seconds: 7200)])
        #expect(entries("start 1 h 30 m timer") == [.start(seconds: 5400)])
        #expect(entries("25 мин") == [.start(seconds: 1500)])
        #expect(entries("90 с") == [.start(seconds: 90)])
        #expect(entries("pizza 90 s").isEmpty)
    }

    @Test func russianQueriesMatchRussianTitles() {
        func russian(_ entry: TimerCommandEntry) -> String {
            if case .start(let s) = entry { return "Запустить таймер на \(s) с" }
            return "Остановить таймер"
        }
        let list = TimerCommandCatalog.entries(state: TimerState(), presets: presets, query: "таймер 90 с",
                                               title: russian, keywords: ["Таймер", "Обратный отсчёт"])
        #expect(list == [.start(seconds: 90)])
        let minutes = TimerCommandCatalog.entries(state: TimerState(), presets: presets, query: "отсчёт 25 мин",
                                                  title: russian, keywords: ["Таймер", "Обратный отсчёт"])
        #expect(minutes == [.start(seconds: 1500)])
    }

    @Test func theLongestRunOfWordsIsTheDuration() {
        #expect(TimerCommandCatalog.typedDuration(in: ["timer", "1", "h", "30", "m"]) == (5400, ["timer"]))
        #expect(TimerCommandCatalog.typedDuration(in: ["90", "s", "timer"]) == (90, ["timer"]))
        #expect(TimerCommandCatalog.typedDuration(in: ["timer"]) == (nil, ["timer"]))
        #expect(TimerCommandCatalog.typedDuration(in: []) == (nil, []))
    }

    @Test func wordsFilterByTitleAndKeywords() {
        let running = TimerState(phase: .running(endDate: t0), total: 300)
        #expect(entries("pause", running) == [.pause])
        #expect(entries("PAUSE", running) == [.pause])
        #expect(entries("pause").isEmpty)                                        // nothing to pause when idle
        #expect(entries("countdown").count == presets.count)
        #expect(entries("stop timer", running) == [.stop])
    }

    @Test func duplicatePresetsAppearOnce() {
        let list = TimerCommandCatalog.all(state: TimerState(), presets: [300, 300, 60])
        #expect(list == [.start(seconds: 300), .start(seconds: 60)])
    }

    @Test func idsAreStable() {
        #expect(TimerCommandEntry.start(seconds: 1500).id == "timer.start.1500")
        #expect(TimerCommandEntry.pause.id == "timer.pause")
        #expect(TimerCommandEntry.addMinute.id == "timer.addMinute")
    }

    @MainActor @Test func paletteCommandsPerformOnTheModel() throws {
        let h = TimerHarness()
        let provider = TimerCommands(model: h.model)
        let start = try #require(provider.commands(matching: "10").first)
        #expect(start.id == "timer.start.600")
        #expect(start.kind == TimerCopy.timer)
        start.perform()
        #expect(h.model.state.total == 600)
        let pause = try #require(provider.commands(matching: "").first)
        #expect(pause.id == "timer.pause")
        pause.perform()
        #expect(h.model.state.isPaused)
    }
}
