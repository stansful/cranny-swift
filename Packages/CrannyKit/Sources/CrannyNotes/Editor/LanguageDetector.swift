// CrannyNotes/Editor/LanguageDetector.swift — "Automatic" language for code mode (DESIGN.md §7.5): the title's
// extension, then a shebang, then a Markdown fence or heading, then a small weighted guess from tell-tale
// phrases. Returns nil when nothing is convincing; the note is then highlighted as generic code.
import Foundation

nonisolated enum LanguageDetector {
    /// Only the start of a note is read: detection runs on every keystroke in code mode.
    static let sampleLength = 4_000

    static func detect(title: String, text: String) -> CodeLanguage? {
        if let byName = CodeLanguage(fileName: title) { return byName }
        let sample = String(text.prefix(sampleLength))
        if let byShebang = shebang(sample) { return byShebang }
        if looksLikeMarkdown(sample) { return .markdown }
        return guess(sample)
    }

    /// `#!/usr/bin/env python3`, `#!/bin/zsh -e`, `#!/usr/bin/swift`.
    static func shebang(_ text: String) -> CodeLanguage? {
        guard text.hasPrefix("#!") else { return nil }
        let line = text.prefix { $0 != "\n" && $0 != "\r" }.dropFirst(2)
        let words = line.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        let program = (first.hasSuffix("/env") ? words.dropFirst().first { !$0.hasPrefix("-") } : first)?
            .split(separator: "/").last.map(String.init) ?? ""
        let name = program.trimmingCharacters(in: .decimalDigits.union(CharacterSet(charactersIn: ".")))
        return CodeLanguage(alias: name) ?? CodeLanguage(alias: program)
    }

    /// A fence on the first line, or a heading/fence/task list early in the note.
    static func looksLikeMarkdown(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(40)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return false }
        if first.hasPrefix("```") || first.hasPrefix("~~~") { return true }
        return lines.contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("# ") || t.hasPrefix("## ") || t.hasPrefix("### ") || t.hasPrefix("```")
                || t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ")
        }
    }

    // MARK: Phrase scoring

    private struct Clue {
        let phrase: String
        let weight: Int
        init(_ phrase: String, _ weight: Int = 2) { self.phrase = phrase; self.weight = weight }
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

    /// The best-scoring language when it is clearly ahead; JSON and YAML by shape.
    static func guess(_ text: String) -> CodeLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeJSON(trimmed) { return .json }
        let lowered = trimmed.lowercased()
        var scores: [(CodeLanguage, Int)] = []
        for (language, phrases) in clues {
            let haystack = language == .sql ? lowered : trimmed
            let score = phrases.reduce(0) { $0 + (haystack.contains($1.phrase) ? $1.weight : 0) }
            if score > 0 { scores.append((language, score)) }
        }
        scores.sort { $0.1 > $1.1 }
        if let best = scores.first, best.1 >= 4, best.1 > (scores.dropFirst().first?.1 ?? 0) { return best.0 }
        if looksLikeYAML(trimmed) { return .yaml }
        return nil
    }

    static func looksLikeJSON(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, let last = trimmed.last,
              (first == "{" && (last == "}" || trimmed.count > 200)) || (first == "[" && (last == "]" || trimmed.count > 200))
        else { return false }
        return trimmed.contains("\":") || first == "["
    }

    /// Most non-empty lines are `key: value`, `- item` or comments, with no braces or semicolons.
    static func looksLikeYAML(_ trimmed: String) -> Bool {
        let lines = trimmed.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(30)
        guard lines.count >= 2, !trimmed.contains(";"), !trimmed.contains("{") else { return false }
        let structured = lines.filter { line in
            line.hasPrefix("#") || line.hasPrefix("- ") || line == "---" || line.contains(": ") || line.hasSuffix(":")
        }
        return structured.count * 4 >= lines.count * 3
    }
}
