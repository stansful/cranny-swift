// CrannyTimer/TimerCommands.swift — ⌘K (DESIGN.md §6.4): "Start N-minute timer" for every preset and for a
// typed duration ("12", "timer 90s"), plus Pause/Resume, +1 min and Stop for the current timer. In-memory filtering
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
    /// - A word that is a duration ("10", "90s", "1:30") offers exactly that timer; the other words must match its
    ///   title or keywords ("timer 10", "start 10").
    /// - Otherwise every word must appear in a command's title or keywords; an empty query lists everything.
    static func entries(state: TimerState, presets: [Int], query: String,
                        title: (TimerCommandEntry) -> String, keywords: [String]) -> [TimerCommandEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let durations = words.compactMap(DurationParser.seconds(from:))
        let otherWords = words.filter { DurationParser.seconds(from: $0) == nil }
        func matches(_ entry: TimerCommandEntry) -> Bool {
            let haystack = ([title(entry)] + keywords).joined(separator: " ")
            return otherWords.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
        if let typed = durations.first {
            let entry = TimerCommandEntry.start(seconds: typed)
            return matches(entry) ? [entry] : []
        }
        return all(state: state, presets: presets).filter(matches)
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
