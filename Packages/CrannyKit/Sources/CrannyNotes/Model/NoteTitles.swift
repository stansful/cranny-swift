// CrannyNotes/Model/NoteTitles.swift — title rules: "Untitled", "Untitled 2" … for new notes, a title from the
// first line for notes recovered after a crash, and the limits of a rename. Pure and unit-tested.
import Foundation

nonisolated enum NoteTitles {
    static let maximumLength = 120
    static let derivedLength = 40

    /// The first free name: `make(nil)` ("Untitled"), then `make(2)`, `make(3)` … ("Untitled 2").
    static func unique(existing: Set<String>, make: (Int?) -> String) -> String {
        let base = make(nil)
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains(make(n)) { n += 1 }
        return make(n)
    }

    /// A short title from the first non-empty line ("## Release" → "Release"), or nil.
    static func derived(from text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            var t = line.trimmingCharacters(in: .whitespaces)
            while let first = t.first, "#>-*`".contains(first) { t.removeFirst() }
            t = t.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            return t.count > derivedLength ? String(t.prefix(derivedLength - 1)) + "…" : t
        }
        return nil
    }

    /// A rename's result: trimmed, one line, at most `maximumLength`; nil keeps the old title.
    static func sanitized(_ proposed: String) -> String? {
        let oneLine = proposed.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }
}
