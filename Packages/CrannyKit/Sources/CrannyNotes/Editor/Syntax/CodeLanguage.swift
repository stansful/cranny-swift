// CrannyNotes/Editor/Syntax/CodeLanguage.swift — the languages code mode highlights (DESIGN.md §7.5: Markdown
// plus common languages). Raw values are persisted in `index.json`: never rename one. Fence names and file
// extensions are looked up in tables built once (every fence is resolved on every keystroke in a Markdown note).
import Foundation

/// A language code mode can highlight. `nil` in a note means "Automatic" (`LanguageDetector`).
nonisolated enum CodeLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case markdown, swift, python, javascript, typescript, json, shell, ruby, go, rust
    case c, cpp, objectiveC = "objc", java, kotlin, html, css, sql, yaml

    var id: String { rawValue }

    /// Proper noun shown in the language menu; not translated.
    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .shell: "Shell"
        case .ruby: "Ruby"
        case .go: "Go"
        case .rust: "Rust"
        case .c: "C"
        case .cpp: "C++"
        case .objectiveC: "Objective-C"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .html: "HTML / XML"
        case .css: "CSS"
        case .sql: "SQL"
        case .yaml: "YAML"
        }
    }

    /// File-name extensions (lowercase, without the dot) that select this language.
    var fileExtensions: [String] {
        switch self {
        case .markdown: ["md", "markdown", "mdown", "mkd"]
        case .swift: ["swift"]
        case .python: ["py", "pyw", "pyi"]
        case .javascript: ["js", "mjs", "cjs", "jsx"]
        case .typescript: ["ts", "tsx", "mts", "cts"]
        case .json: ["json", "jsonc", "geojson"]
        case .shell: ["sh", "bash", "zsh", "fish", "command"]
        case .ruby: ["rb", "rake", "gemspec"]
        case .go: ["go"]
        case .rust: ["rs"]
        case .c: ["c", "h"]
        case .cpp: ["cpp", "cc", "cxx", "hpp", "hh", "hxx"]
        case .objectiveC: ["m", "mm"]
        case .java: ["java"]
        case .kotlin: ["kt", "kts"]
        case .html: ["html", "htm", "xhtml", "xml", "plist", "svg", "xib", "storyboard"]
        case .css: ["css", "scss", "less"]
        case .sql: ["sql"]
        case .yaml: ["yaml", "yml"]
        }
    }

    /// Names accepted after a Markdown fence (```` ```swift ````) and in a shebang.
    var aliases: [String] {
        switch self {
        case .markdown: ["markdown", "md"]
        case .swift: ["swift"]
        case .python: ["python", "python3", "py"]
        case .javascript: ["javascript", "js", "node", "jsx"]
        case .typescript: ["typescript", "ts", "tsx", "deno"]
        case .json: ["json", "jsonc"]
        case .shell: ["shell", "sh", "bash", "zsh", "console", "fish"]
        case .ruby: ["ruby", "rb"]
        case .go: ["go", "golang"]
        case .rust: ["rust", "rs"]
        case .c: ["c", "h"]
        case .cpp: ["cpp", "c++", "cc", "cxx", "hpp"]
        case .objectiveC: ["objc", "objective-c", "objectivec", "obj-c"]
        case .java: ["java"]
        case .kotlin: ["kotlin", "kt"]
        case .html: ["html", "xml", "xhtml", "svg", "plist"]
        case .css: ["css", "scss", "less"]
        case .sql: ["sql", "postgres", "postgresql", "mysql", "sqlite"]
        case .yaml: ["yaml", "yml"]
        }
    }

    /// The language a fence info string or shebang interpreter names ("Swift", "c++", "python3").
    init?(alias: String) {
        guard !alias.isEmpty, let match = Self.byAlias[alias.trimmingCharacters(in: .whitespaces).lowercased()] else {
            return nil
        }
        self = match
    }

    /// The language of a file name's extension ("deploy.md" → Markdown).
    init?(fileName: String) {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return nil }
        let ext = fileName[fileName.index(after: dot)...].trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.byExtension[ext] else { return nil }
        self = match
    }

    /// Every alias → its language. A name two languages list belongs to the first in `allCases` order.
    private static let byAlias = table(\.aliases)
    /// Every file extension → its language, with the same precedence.
    private static let byExtension = table(\.fileExtensions)

    private static func table(_ names: (CodeLanguage) -> [String]) -> [String: CodeLanguage] {
        Dictionary(allCases.flatMap { language in names(language).map { ($0, language) } }, uniquingKeysWith: { first, _ in first })
    }
}
