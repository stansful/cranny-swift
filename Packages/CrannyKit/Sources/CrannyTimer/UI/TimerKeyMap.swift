// CrannyTimer/UI/TimerKeyMap.swift — the focused Timer widget's keyboard map (DESIGN.md §16: digits ↩ start "25" /
// "90s" · Space pause/resume · ⌫ reset; plus ↑ ↓ ±1 min and Esc to drop a typed entry). Pure, so it is unit-tested;
// `TimerFace` turns `KeyPress`es into `TimerKey`s and performs the returned command.
import Foundation

nonisolated enum TimerKey: Equatable, Sendable {
    case returnKey, delete, escape, up, down, space
    case character(Character)
}

nonisolated enum TimerKeyCommand: Equatable, Sendable {
    case none
    case start(seconds: Int)
    case startSetup, togglePause, stop, clearDraft
    case adjust(minutes: Int)
}

nonisolated enum TimerKeyMap {
    /// What the face is showing, as far as keys care.
    enum Phase: Equatable, Sendable { case idle, counting, done }

    struct Result: Equatable, Sendable {
        /// false = not ours: let the panel have it (Esc closes, Space activates elsewhere…).
        var handled: Bool
        /// The typed entry after the key.
        var entry: String
        var command: TimerKeyCommand = .none
    }

    static func handle(_ key: TimerKey, entry: String, phase: Phase, hasDraft: Bool) -> Result {
        switch key {
        case .returnKey:
            if !entry.isEmpty {
                guard let seconds = DurationParser.seconds(from: entry) else { return Result(handled: true, entry: entry) }
                return Result(handled: true, entry: "", command: .start(seconds: seconds))     // invalid: the hint stays
            }
            switch phase {
            case .idle: return Result(handled: true, entry: entry, command: .startSetup)
            case .counting: return Result(handled: true, entry: entry, command: .togglePause)
            case .done: return Result(handled: true, entry: entry, command: .stop)
            }
        case .delete:
            if !entry.isEmpty { return Result(handled: true, entry: String(entry.dropLast())) }
            if phase != .idle { return Result(handled: true, entry: entry, command: .stop) }
            return hasDraft ? Result(handled: true, entry: entry, command: .clearDraft) : Result(handled: false, entry: entry)
        case .escape:
            return entry.isEmpty ? Result(handled: false, entry: entry) : Result(handled: true, entry: "")
        case .up:
            return Result(handled: true, entry: entry, command: .adjust(minutes: 1))
        case .down:
            return Result(handled: true, entry: entry, command: .adjust(minutes: -1))
        case .space:
            if !entry.isEmpty { return type(" ", into: entry) }                              // "1h 30m"
            return phase == .counting ? Result(handled: true, entry: entry, command: .togglePause)
                                      : Result(handled: false, entry: entry)
        case .character(let c):
            guard DurationParser.accepts(c), c != " " else { return Result(handled: false, entry: entry) }
            return type(c, into: entry)
        }
    }

    private static func type(_ c: Character, into entry: String) -> Result {
        guard entry.count < DurationParser.maximumLength else { return Result(handled: true, entry: entry) }
        return Result(handled: true, entry: entry + String(c))
    }
}
