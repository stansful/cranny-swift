// CrannyTimer/TimerCommands.swift — ⌘K (DESIGN.md §6.4): "Start N-minute timer" for every preset and for a
// typed duration ("12", "timer 90 s"), plus Pause/Resume, +1 min and Stop for the current timer. In-memory filtering
// only (queried on every keystroke).
import CrannyCore
import Foundation

/// What a command does; the catalogue is pure so its matching rules are unit-tested.
nonisolated enum TimerCommandEntry: Hashable, Sendable {
    case start(seconds: Int)
    case pause, resume, addMinute, stop

    var id: CommandID {
        switch self {
        case .start(let seconds): CommandID("timer.start.\(seconds)")
        case .pause: "timer.pause"
        case .resume: "timer.resume"
        case .addMinute: "timer.addMinute"
        case .stop: "timer.stop"
        }
    }
}

nonisolated enum TimerCommandCatalog {
    /// The commands for `query`, best first.
    /// - A duration in the query ("10", "90s", "90 s", "1 h 30 m", "25 мин", "1:30") offers exactly that timer; the
    ///   words around it must match its title or keywords ("timer 10", "таймер 90 с").
    /// - Otherwise every word must appear in a command's title or keywords; an empty query lists everything.
    static func entries(state: TimerState, presets: [Int], query: String,
                        title: (TimerCommandEntry) -> String, keywords: [String]) -> [TimerCommandEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let (typed, otherWords) = typedDuration(in: words)
        func matches(_ entry: TimerCommandEntry) -> Bool {
            let haystack = ([title(entry)] + keywords).joined(separator: " ")
            return otherWords.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        if let typed {
            let entry = TimerCommandEntry.start(seconds: typed)
            return matches(entry) ? [entry] : []
        }
        return all(state: state, presets: presets).filter(matches)
    }

    /// Words in the longest duration ("1 h 30 m 15 s"); longer runs are not tried, so a long query stays cheap.
    static let longestDurationRun = 6

    /// The longest run of consecutive words that `DurationParser` reads as ONE duration (the earliest of equally long
    /// runs), and the words around it. Parsing the run as a whole keeps a unit typed after a space ("90 s") with its
    /// number, as the widget's own entry does, instead of reading "90" as minutes and "s" as a search word.
    static func typedDuration(in words: [String]) -> (seconds: Int?, otherWords: [String]) {
        for length in stride(from: min(words.count, longestDurationRun), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let end = start + length
                if let seconds = DurationParser.seconds(from: words[start..<end].joined(separator: " ")) {
                    return (seconds, Array(words[..<start] + words[end...]))
                }
            }
        }
        return (nil, words)
    }

    /// Everything that applies to `state`: the controls of the current timer first, then the presets.
    static func all(state: TimerState, presets: [Int]) -> [TimerCommandEntry] {
        let controls: [TimerCommandEntry] = switch state.phase {
        case .idle: []
        case .running: [.pause, .addMinute, .stop]
        case .paused: [.resume, .addMinute, .stop]
        case .done: [.stop, .addMinute]
        }
        var seen = Set<Int>()
        return controls + presets.filter { seen.insert($0).inserted }.map { .start(seconds: $0) }
    }

    /// The localized title of an entry.
    static func title(_ entry: TimerCommandEntry) -> String {
        switch entry {
        case .start(let seconds): TimerCopy.startTitle(seconds: seconds)
        case .pause: TimerCopy.pause
        case .resume: TimerCopy.resume
        case .addMinute: TimerCopy.addMinute
        case .stop: TimerCopy.stop
        }
    }
}

final class TimerCommands: PaletteCommandProvider {
    let model: TimerModel
    init(model: TimerModel) { self.model = model }

    func commands(matching query: String) -> [PaletteCommand] {
        let keywords = TimerCopy.commandKeywords
        return TimerCommandCatalog.entries(state: model.state, presets: model.presets, query: query,
                                           title: TimerCommandCatalog.title, keywords: keywords)
            .map { entry in
                PaletteCommand(id: entry.id, title: TimerCommandCatalog.title(entry), kind: TimerCopy.timer,
                               symbol: Self.symbol(entry), keywords: keywords) { [model] in Self.perform(entry, on: model) }
            }
    }

    private static func symbol(_ entry: TimerCommandEntry) -> String {
        switch entry {
        case .start, .addMinute: "timer"
        case .pause: "pause.fill"
        case .resume: "play.fill"
        case .stop: "stop.fill"
        }
    }

    static func perform(_ entry: TimerCommandEntry, on model: TimerModel) {
        switch entry {
        case .start(let seconds): model.start(seconds: seconds)
        case .pause: model.pause()
        case .resume: model.resume()
        case .addMinute: model.addMinute()
        case .stop: model.stop()
        }
    }
}
