// CrannyTimer/UI/DurationParser.swift — typed durations for the focused Timer widget and ⌘K (DESIGN.md §7.7, §16):
// "25" = 25 min, "90s" = 90 s, "1h30m", "1:30" (m:ss), "1:30:00" (h:mm:ss), "2.5" = 2 min 30 s, plus Russian units
// ("90с", "25 мин", "1ч 30м"). Pure and locale-independent; unit-tested.
import Foundation

nonisolated enum DurationParser {
    /// Longest text the widget accepts while typing ("1h 30m 15s" fits).
    static let maximumLength = 12

    private enum Unit: Int, Comparable {
        case seconds = 1, minutes = 60, hours = 3600
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        var smaller: Unit? { switch self { case .hours: .minutes; case .minutes: .seconds; case .seconds: nil } }

        init?(word: String) {
            switch word {
            case "h", "hr", "hrs", "hour", "hours", "ч", "час", "часа", "часов": self = .hours
            case "m", "min", "mins", "minute", "minutes", "м", "мин", "минута", "минуту", "минуты", "минут": self = .minutes
            case "s", "sec", "secs", "second", "seconds", "с", "сек", "секунда", "секунду", "секунды", "секунд": self = .seconds
            default: return nil
            }
        }
    }

    /// Whole seconds in `TimerLimits.minimum…maximum`, or nil if `text` is not a duration.
    static func seconds(from text: String) -> Int? {
        let normalized = text.lowercased()
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let value = normalized.contains(":") ? clockForm(normalized) : unitForm(normalized)
        guard let value, value.isFinite else { return nil }
        let seconds = value.rounded()
        guard seconds >= TimerLimits.minimum, seconds <= TimerLimits.maximum else { return nil }
        return Int(seconds)
    }

    /// Characters the widget lets the user type (digits, separators, unit letters in English and Russian).
    static func accepts(_ character: Character) -> Bool {
        let c = Character(character.lowercased())
        return c.isASCIIDigit || ".,: ".contains(c) || unitLetters.contains(c)
    }

    /// Whether the focused widget takes `character` as the next one of `entry`: digits and "." always (".5"), unit
    /// letters and the separators ",", ":" and " " only once the entry holds a digit. So an entry always starts like a
    /// number, and a word typed over the focused face ("note", "test") is never captured.
    static func canAppend(_ character: Character, to entry: String) -> Bool {
        let c = Character(character.lowercased())
        if c.isASCIIDigit || c == "." { return true }
        return accepts(c) && entry.contains(where: \.isASCIIDigit)
    }

    /// Every letter of the unit words below ("hours minutes seconds", "часов минуты секунд").
    private static let unitLetters = Set("hoursminutesecd" + "часовминутыекд")

    // MARK: - Forms

    /// "m:ss" or "h:mm:ss" (minutes and seconds after a colon must be two digits below 60).
    private static func clockForm(_ s: String) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count,
              parts.dropFirst().allSatisfy({ $0.count == 2 }),
              numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return Double(numbers.reduce(0) { $0 * 60 + $1 })
    }

    /// Number–unit pairs in descending unit order, each unit once: "25", "90s", "1h30m", "1h 30", "1 мин 30 сек".
    /// A lone number is minutes; a trailing number without a unit takes the next smaller unit ("1h30" = 1 h 30 min).
    private static func unitForm(_ s: String) -> Double? {
        var scanner = Substring(s)
        var total = 0.0
        var previous: Unit?
        var sawNumber = false
        while true {
            scanner = scanner.drop { $0 == " " }
            if scanner.isEmpty { break }
            guard let number = scanNumber(&scanner) else { return nil }
            scanner = scanner.drop { $0 == " " }
            let word = String(scanner.prefix { $0.isLetter })
            scanner = scanner.dropFirst(word.count).drop { $0 == "." }
            let unit: Unit
            if word.isEmpty {
                guard scanner.drop(while: { $0 == " " }).isEmpty else { return nil }   // only the last number may omit it
                guard let implied = previous.map({ $0.smaller }) ?? .minutes else { return nil }
                unit = implied
            } else {
                guard let parsed = Unit(word: word) else { return nil }
                unit = parsed
            }
            if let previous, unit >= previous { return nil }                          // descending, each unit once
            total += number * Double(unit.rawValue)
            previous = unit
            sawNumber = true
        }
        return sawNumber ? total : nil
    }

    /// Digits with at most one decimal point ("2", "2.5", ".5").
    private static func scanNumber(_ scanner: inout Substring) -> Double? {
        let text = scanner.prefix { $0.isASCIIDigit || $0 == "." }
        guard !text.isEmpty, text.filter({ $0 == "." }).count <= 1, text != "." else { return nil }
        scanner = scanner.dropFirst(text.count)
        return Double(text)
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
