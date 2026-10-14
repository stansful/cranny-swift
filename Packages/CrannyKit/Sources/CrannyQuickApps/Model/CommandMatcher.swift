// CrannyQuickApps/Model/CommandMatcher.swift — ⌘K matching and the ⌥1–⌥9 key combos (pure, tested).
import CrannyCore
import Foundation

nonisolated enum CommandMatcher {
    /// How well `query` matches any of `texts`: 2 = prefix, 1 = start of a word, 0 = anywhere, nil = no match.
    /// Case, diacritics and width are ignored ("сафари" never matches "Safari", but "SAF" does). Empty query = 0.
    static func score(_ texts: [String], query: String) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return 0 }
        var best: Int?
        for text in texts {
            guard let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) else { continue }
            let score: Int
            if range.lowerBound == text.startIndex {
                score = 2
            } else if let before = text[..<range.lowerBound].last, !(before.isLetter || before.isNumber) {
                score = 1
            } else {
                score = 0
            }
            best = max(best ?? score, score)
        }
        return best
    }

    /// ⌥1…⌥9 for tile `index` 0…8 (Carbon virtual key codes of the number row; display "⌥1").
    static func optionDigit(_ index: Int) -> KeyCombo? {
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]     // kVK_ANSI_1 … kVK_ANSI_9
        guard codes.indices.contains(index) else { return nil }
        return KeyCombo(keyCode: codes[index], modifiers: [.option], display: "⌥\(index + 1)")
    }
}
