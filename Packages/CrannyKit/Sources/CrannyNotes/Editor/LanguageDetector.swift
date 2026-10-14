// CrannyNotes/Editor/LanguageDetector.swift — "Automatic" language for code mode (DESIGN.md §7.5): the title's
// extension, then a shebang, then a Markdown fence or heading, then a small weighted guess from tell-tale
// phrases. Returns nil when nothing is convincing; the note is then highlighted as generic code.
// Never on the keystroke path: `NotesModel` re-detects at most every 0.4 s while a note changes, over the first
// 2 000 UTF-16 units only, in one pass that looks for every phrase at once (≈ 0.1 ms in Release).
import Foundation

nonisolated enum LanguageDetector {
    /// Only the start of a note is read (UTF-16 units).
    static let sampleLength = 2_000

    static func detect(title: String, text: String) -> CodeLanguage? {
        if let byName = CodeLanguage(fileName: title) { return byName }
        let sample = Self.sample(text)
        if let byShebang = shebang(sample) { return byShebang }
        if looksLikeMarkdown(sample) { return .markdown }
        return guess(sample)
    }

    /// The first `sampleLength` UTF-16 units, read in order: `utf16.prefix(_:)` would index a long non-ASCII
    /// string's UTF-16 view first, which walks all of it (≈ 1 ms for 290 000 Cyrillic units).
    static func sample(_ text: String) -> [UInt16] {
        var units: [UInt16] = []
        units.reserveCapacity(sampleLength)
        for unit in text.utf16 {
            guard units.count < sampleLength else { break }
            units.append(unit)
        }
        return units
    }

    /// `#!/usr/bin/env python3`, `#!/bin/zsh -e`, `#!/usr/bin/swift`.
    static func shebang(_ text: String) -> CodeLanguage? { shebang(sample(text)) }

    static func shebang(_ units: [UInt16]) -> CodeLanguage? {
        guard units.count >= 2, units[0] == 0x23, units[1] == 0x21 else { return nil }   // #!
        let lineEnd = units.firstIndex(where: SourceText.isNewline) ?? units.count
        let line = String(decoding: units[2..<lineEnd], as: UTF16.self)
        let words = line.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        let program = (first.hasSuffix("/env") ? words.dropFirst().first { !$0.hasPrefix("-") } : first)?
            .split(separator: "/").last.map(String.init) ?? ""
        let name = program.trimmingCharacters(in: .decimalDigits.union(CharacterSet(charactersIn: ".")))
        return CodeLanguage(alias: name) ?? CodeLanguage(alias: program)
    }

    /// A fence on the first line, or a heading/fence/task list in the first 40 lines.
    static func looksLikeMarkdown(_ units: [UInt16]) -> Bool {
        let lines = Array(Lines(units: units, range: 0..<units.count).prefix(40))
        guard let first = lines.first else { return false }
        if has(units, first, prefix: "```") || has(units, first, prefix: "~~~") { return true }
        return lines.contains { line in
            Self.markdownLinePrefixes.contains { has(units, line, prefix: $0) }
        }
    }

    private static let markdownLinePrefixes = ["# ", "## ", "### ", "```", "- [ ] ", "- [x] "].map { Array($0.utf16) }

    // MARK: Phrase scoring

    private struct Clue {
        let phrase: [UInt16]
        let weight: Int
        init(_ phrase: String, _ weight: Int = 2) { self.phrase = Array(phrase.utf16); self.weight = weight }
    }

    private static let clues: [(CodeLanguage, [Clue])] = [
        (.swift, [Clue("import SwiftUI", 6), Clue("import Foundation", 5), Clue("import UIKit", 6), Clue("import AppKit", 6),
                  Clue("func "), Clue("guard let ", 4), Clue("if let ", 3), Clue("@MainActor", 5), Clue("@Observable", 5),
                  Clue("struct ", 1), Clue("-> ", 1), Clue("var body: some View", 6), Clue("extension ", 2), Clue("let ", 1)]),
        (.python, [Clue("def ", 3), Clue("import ", 1), Clue("from ", 1), Clue("elif ", 4), Clue("self.", 2), Clue("print(", 2),
                   Clue("__init__", 5), Clue("None", 2), Clue("True", 1), Clue("    return ", 1), Clue("if __name__", 6)]),
        (.javascript, [Clue("const ", 2), Clue("function ", 2), Clue("=> ", 2), Clue("console.log", 5), Clue("require(", 4),
                       Clue("module.exports", 6), Clue("document.", 4), Clue("let ", 1), Clue("===", 3)]),
        (.typescript, [Clue("interface ", 3), Clue(": string", 4), Clue(": number", 4), Clue("export type ", 5),
                       Clue(": boolean", 4), Clue("readonly ", 2)]),
        (.go, [Clue("package main", 8), Clue("func main()", 6), Clue(":= ", 3), Clue("fmt.", 5), Clue("err != nil", 6)]),
        (.rust, [Clue("fn ", 3), Clue("let mut ", 6), Clue("impl ", 4), Clue("pub fn ", 6), Clue("println!", 6), Clue("use std::", 8),
                 Clue("&str", 4), Clue("Vec<", 3)]),
        (.c, [Clue("#include", 6), Clue("int main(", 5), Clue("printf(", 4), Clue("malloc(", 5), Clue("NULL", 2)]),
        (.cpp, [Clue("std::", 6), Clue("#include <iostream>", 8), Clue("cout <<", 6), Clue("template<", 5), Clue("namespace ", 3)]),
        (.objectiveC, [Clue("@interface", 8), Clue("@implementation", 8), Clue("#import", 5), Clue("NSString *", 6), Clue("[self ", 4)]),
        (.java, [Clue("public class ", 6), Clue("System.out.", 7), Clue("public static void", 6), Clue("private final ", 4),
                 Clue("import java.", 8)]),
        (.kotlin, [Clue("fun ", 4), Clue("val ", 3), Clue("println(", 2), Clue("data class ", 6), Clue("import kotlin", 8)]),
        (.ruby, [Clue("def ", 2), Clue("\nend", 4), Clue("puts ", 4), Clue("require '", 5), Clue("attr_accessor", 6), Clue(".each do", 6)]),
        (.shell, [Clue("echo ", 3), Clue("\nfi", 5), Clue("then\n", 4), Clue("$(", 3), Clue("export ", 2), Clue("sudo ", 4),
                  Clue("brew ", 4), Clue("cd ", 2), Clue("git ", 2), Clue("&& ", 1), Clue("--", 1)]),
        (.sql, [Clue("select ", 4), Clue(" from ", 3), Clue(" where ", 3), Clue("insert into", 6), Clue("create table", 7),
                Clue("update ", 2), Clue("join ", 2), Clue("group by", 5), Clue("order by", 4)]),
        (.css, [Clue("px;", 5), Clue("color:", 3), Clue("margin:", 4), Clue("padding:", 4), Clue("display:", 4), Clue("@media", 6),
                Clue("font-size:", 5)]),
        (.html, [Clue("<!DOCTYPE", 8), Clue("<html", 8), Clue("<div", 5), Clue("<?xml", 8), Clue("</", 2), Clue("<p>", 4),
                 Clue("<body", 6), Clue("<plist", 8)]),
    ]

    /// Every clue once, flattened, with its language's index; SQL matches ignoring ASCII case.
    private struct Phrase {
        let language: Int
        let units: [UInt16]
        let weight: Int
        let ignoresCase: Bool
    }

    private static let phrases: [Phrase] = clues.enumerated().flatMap { index, entry in
        entry.1.map { Phrase(language: index, units: $0.phrase, weight: $0.weight, ignoresCase: entry.0 == .sql) }
    }

    /// Phrase indices by their first unit (every phrase starts with ASCII; case-insensitive ones by the lowercase).
    private static let phrasesByFirstUnit: [[Int]] = {
        var table = [[Int]](repeating: [], count: 128)
        for (index, phrase) in phrases.enumerated() {
            guard let first = phrase.units.first, first < 128 else { continue }
            table[Int(phrase.ignoresCase ? SourceText.lowercased(first) : first)].append(index)
        }
        return table
    }()

    /// The best-scoring language when it is clearly ahead; JSON and YAML by shape.
    static func guess(_ units: [UInt16]) -> CodeLanguage? {
        var lower = 0, upper = units.count
        while lower < upper && SourceText.isWhitespace(units[lower]) { lower += 1 }
        while upper > lower && SourceText.isWhitespace(units[upper - 1]) { upper -= 1 }
        guard lower < upper else { return nil }
        let trimmed = lower..<upper
        if looksLikeJSON(units, trimmed) { return .json }
        // One pass: at each unit, only the phrases that start with it are compared.
        var found = [Bool](repeating: false, count: phrases.count)
        for i in trimmed {
            let unit = units[i]
            guard unit < 128 else { continue }
            for candidate in phrasesByFirstUnit[Int(unit)] where !found[candidate] {
                found[candidate] = matches(phrases[candidate], units, at: i, end: upper)
            }
            let folded = SourceText.lowercased(unit)                            // "SELECT": SQL ignores case
            guard folded != unit else { continue }
            for candidate in phrasesByFirstUnit[Int(folded)] where phrases[candidate].ignoresCase && !found[candidate] {
                found[candidate] = matches(phrases[candidate], units, at: i, end: upper)
            }
        }
        var scores = [Int](repeating: 0, count: clues.count)
        for (index, phrase) in phrases.enumerated() where found[index] { scores[phrase.language] += phrase.weight }
        let ranked = scores.enumerated().filter { $0.element > 0 }.sorted { $0.element > $1.element }
        if let best = ranked.first, best.element >= 4, best.element > (ranked.dropFirst().first?.element ?? 0) {
            return clues[best.offset].0
        }
        if looksLikeYAML(units, trimmed) { return .yaml }
        return nil
    }

    private static func matches(_ phrase: Phrase, _ units: [UInt16], at index: Int, end: Int) -> Bool {
        guard index + phrase.units.count <= end else { return false }
        for (offset, expected) in phrase.units.enumerated() {
            let unit = units[index + offset]
            if unit != expected && !(phrase.ignoresCase && SourceText.lowercased(unit) == expected) { return false }
        }
        return true
    }

    // MARK: Shapes

    private static func looksLikeJSON(_ units: [UInt16], _ trimmed: Range<Int>) -> Bool {
        let first = units[trimmed.lowerBound], last = units[trimmed.upperBound - 1]
        let long = trimmed.count > 200
        guard (first == 0x7B && (last == 0x7D || long)) || (first == 0x5B && (last == 0x5D || long)) else { return false }
        if first == 0x5B { return true }
        return trimmed.dropLast().contains { units[$0] == 0x22 && units[$0 + 1] == 0x3A }                    // "key":
    }

    /// Most non-empty lines are `key: value`, `- item` or comments, with no braces or semicolons.
    private static func looksLikeYAML(_ units: [UInt16], _ trimmed: Range<Int>) -> Bool {
        guard !units[trimmed].contains(0x3B), !units[trimmed].contains(0x7B) else { return false }           // ; {
        let lines = Array(Lines(units: units, range: trimmed).prefix(30))
        guard lines.count >= 2 else { return false }
        let structured = lines.filter { line in
            has(units, line, prefix: "#") || has(units, line, prefix: "- ") || isExactly(units, line, "---")
                || units[line].indices.contains { units[$0] == 0x3A && $0 + 1 < line.upperBound && units[$0 + 1] == 0x20 }
                || units[line.upperBound - 1] == 0x3A
        }
        return structured.count * 4 >= lines.count * 3
    }

    // MARK: Lines

    /// The non-empty lines of `range`, without their leading and trailing spaces and tabs.
    private struct Lines: Sequence, IteratorProtocol {
        let units: [UInt16]
        var range: Range<Int>

        mutating func next() -> Range<Int>? {
            var start = range.lowerBound
            while start < range.upperBound {
                var end = start
                while end < range.upperBound && !SourceText.isNewline(units[end]) { end += 1 }
                range = Swift.min(end + 1, range.upperBound)..<range.upperBound
                var lower = start, upper = end
                while lower < upper && SourceText.isSpace(units[lower]) { lower += 1 }
                while upper > lower && SourceText.isSpace(units[upper - 1]) { upper -= 1 }
                if lower < upper { return lower..<upper }
                start = range.lowerBound
            }
            return nil
        }
    }

    private static func has(_ units: [UInt16], _ line: Range<Int>, prefix: String) -> Bool {
        has(units, line, prefix: Array(prefix.utf16))
    }

    private static func has(_ units: [UInt16], _ line: Range<Int>, prefix: [UInt16]) -> Bool {
        line.count >= prefix.count && units[line.lowerBound..<(line.lowerBound + prefix.count)].elementsEqual(prefix)
    }

    private static func isExactly(_ units: [UInt16], _ line: Range<Int>, _ text: String) -> Bool {
        units[line].elementsEqual(text.utf16)
    }
}
