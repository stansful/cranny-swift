// CrannyQuickApps/Shortcuts/ShortcutListParser.swift — `shortcuts list --show-identifiers` → shortcuts (pure).
//
// The CLI prints one shortcut per line as "Name (UUID)" (R3 §6, re-captured on macOS 27.0.1). Names may contain
// parentheses, Cyrillic, emoji and trailing spaces, so the identifier is the LAST parenthesised group of a line
// and must parse as a UUID. Lines without one are skipped (a list printed without --show-identifiers yields []).
import Foundation

/// One shortcut in Shortcuts.app.
nonisolated struct ShortcutInfo: Hashable, Sendable, Identifiable {
    /// Uppercase UUID string, the identifier `shortcuts run` accepts.
    let id: String
    let name: String
}

nonisolated enum ShortcutListParser {
    /// Every shortcut in the CLI's output, in its order; a repeated identifier keeps its first line.
    static func parse(_ data: Data) -> [ShortcutInfo] {
        parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ output: String) -> [ShortcutInfo] {
        var seen = Set<String>()
        var result: [ShortcutInfo] = []
        output.enumerateLines { line, _ in
            guard let info = parseLine(line), seen.insert(info.id).inserted else { return }
            result.append(info)
        }
        return result
    }

    /// "Name (UUID)" → the shortcut; nil when the line does not end in a parenthesised UUID.
    static func parseLine(_ line: String) -> ShortcutInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        guard trimmed.hasSuffix(")"), let open = trimmed.range(of: "(", options: .backwards) else { return nil }
        let candidate = trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)]
        guard let uuid = UUID(uuidString: String(candidate)) else { return nil }
        let name = trimmed[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
        return ShortcutInfo(id: uuid.uuidString, name: name)
    }
}
