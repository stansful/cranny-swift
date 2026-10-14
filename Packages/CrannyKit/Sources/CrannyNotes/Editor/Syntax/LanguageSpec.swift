// CrannyNotes/Editor/Syntax/LanguageSpec.swift — the table that drives `CodeTokenizer` for the C-like and
// scripting languages. Original word lists (language keywords are facts, not anyone's code).
import Foundation

/// How one language spells comments, strings, keywords and the like.
nonisolated struct LanguageSpec: Sendable {
    nonisolated struct Delimited: Sendable {
        var open: String
        var close: String
        /// Backslash escapes the next character.
        var escapes = true
        /// May span lines (otherwise the run stops at the end of the line).
        var multiline = false
    }

    var keywords: Set<String> = []
    var types: Set<String> = []
    /// `Capitalized` identifiers are types (Swift, Kotlin, Java, TypeScript, Rust, Python classes).
    var capitalizedTypes = false
    /// Keywords match in any case (SQL). Such a spec lists `keywords` in lowercase: words are lowercased to match.
    var caseInsensitiveKeywords = false
    var lineComments: [String] = []
    /// Shell: `#` opens a comment only at the start of a line or after whitespace (`a#b` is a word).
    var lineCommentNeedsBoundary = false
    var blockComment: Delimited?
    var nestedBlockComments = false
    /// Longest opener first (`"""` before `"`).
    var strings: [Delimited] = []
    /// Identifier prefixes glued to a string (`r"…"`, `f'…'`, `b"…"`, `@"…"`).
    var stringPrefixes: Set<String> = []
    /// `@name` → keyword (Swift attributes, Python decorators, Java/Kotlin annotations, Objective-C `@interface`).
    var attributePrefix = false
    /// `#name` → keyword (C preprocessor at line start, Swift `#if`/`#available` anywhere).
    var directives: DirectiveRule = .none
    /// `$name`, `${…}`, `$1` → type (shell).
    var dollarVariables = false
    /// `name(` → function.
    var detectsFunctions = true
    /// Rust: `name!(` is a macro call → function; `'a` is a lifetime, `'x'` a character.
    var rust = false
    /// Ruby: `:symbol` → string; `@ivar` → type.
    var ruby = false

    nonisolated enum DirectiveRule: Sendable { case none, lineStart, anywhere }
}

// MARK: - The specs

nonisolated extension LanguageSpec {
    static func spec(for language: CodeLanguage) -> LanguageSpec? {
        switch language {
        case .swift: swift
        case .python: python
        case .javascript: javascript
        case .typescript: typescript
        case .shell: shell
        case .ruby: ruby
        case .go: go
        case .rust: rust
        case .c: c
        case .cpp: cpp
        case .objectiveC: objectiveC
        case .java: java
        case .kotlin: kotlin
        case .sql: sql
        case .markdown, .json, .html, .css, .yaml: nil      // dedicated tokenizers
        }
    }

    /// Unknown code ("Automatic" found nothing): strings, numbers, `//` and `/* */` comments only.
    /// Single quotes are not strings here, so an apostrophe in "don't" never colours the rest of a line.
    static let generic = LanguageSpec(
        lineComments: ["//"], blockComment: cBlock,
        strings: [.init(open: "\"", close: "\""), .init(open: "`", close: "`", multiline: true)],
        detectsFunctions: false)

    private static let cBlock = Delimited(open: "/*", close: "*/", escapes: false, multiline: true)
    private static let doubleQuoted = Delimited(open: "\"", close: "\"")
    private static let singleQuoted = Delimited(open: "'", close: "'")

    static let swift = LanguageSpec(
        keywords: ["associatedtype", "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue",
                   "convenience", "default", "defer", "deinit", "didSet", "do", "dynamic", "else", "enum", "extension",
                   "fallthrough", "false", "fileprivate", "final", "for", "func", "get", "guard", "if", "import", "in",
                   "indirect", "init", "inout", "internal", "is", "isolated", "lazy", "let", "macro", "mutating", "nil",
                   "nonisolated", "nonmutating", "open", "operator", "optional", "override", "package", "private",
                   "protocol", "public", "repeat", "required", "rethrows", "return", "self", "Self", "set", "some",
                   "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
                   "unowned", "var", "weak", "where", "while", "willSet", "consume", "borrowing", "consuming", "sending"],
        types: ["Int", "Double", "Float", "Bool", "String", "Character", "Void", "Any", "AnyObject", "Never"],
        capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock, nestedBlockComments: true,
        strings: [.init(open: "#\"\"\"", close: "\"\"\"#", escapes: false, multiline: true),
                  .init(open: "\"\"\"", close: "\"\"\"", multiline: true),
                  .init(open: "#\"", close: "\"#", escapes: false), doubleQuoted],
        attributePrefix: true, directives: .anywhere)

    static let python = LanguageSpec(
        keywords: ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "case", "class", "continue",
                   "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is",
                   "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return", "self", "try", "while", "with",
                   "yield"],
        types: ["int", "float", "str", "bool", "bytes", "list", "dict", "set", "tuple", "object", "type", "complex",
                "frozenset", "bytearray"],
        capitalizedTypes: true, lineComments: ["#"],
        strings: [.init(open: "\"\"\"", close: "\"\"\"", multiline: true), .init(open: "'''", close: "'''", multiline: true),
                  doubleQuoted, singleQuoted],
        stringPrefixes: ["r", "u", "f", "b", "rb", "br", "fr", "rf", "R", "F", "B", "U"],
        attributePrefix: true)

    private static let javascriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
        "else", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "import", "in",
        "instanceof", "let", "new", "null", "of", "return", "set", "static", "super", "switch", "this", "throw", "true",
        "try", "typeof", "undefined", "var", "void", "while", "with", "yield"]
    private static let javascriptStrings: [Delimited] = [.init(open: "`", close: "`", multiline: true), doubleQuoted, singleQuoted]

    static let javascript = LanguageSpec(
        keywords: javascriptKeywords, capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock,
        strings: javascriptStrings, attributePrefix: true)

    static let typescript = LanguageSpec(
        keywords: javascriptKeywords.union(["abstract", "as", "declare", "enum", "implements", "interface", "is",
                                            "keyof", "namespace", "private", "protected", "public", "readonly",
                                            "satisfies", "type", "infer", "override"]),
        types: ["string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint", "void"],
        capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock, strings: javascriptStrings,
        attributePrefix: true)

    static let shell = LanguageSpec(
        keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac",
                   "function", "return", "local", "export", "readonly", "declare", "set", "unset", "shift", "source",
                   "exit", "break", "continue", "select", "time", "echo", "cd", "eval", "exec", "trap", "true", "false"],
        lineComments: ["#"], lineCommentNeedsBoundary: true,
        strings: [.init(open: "\"", close: "\"", multiline: true), .init(open: "'", close: "'", escapes: false, multiline: true)],
        dollarVariables: true, detectsFunctions: false)

    static let ruby = LanguageSpec(
        keywords: ["BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else",
                   "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo",
                   "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when",
                   "while", "yield", "require", "require_relative", "attr_accessor", "attr_reader", "attr_writer",
                   "private", "protected", "public", "puts", "raise", "lambda", "proc"],
        capitalizedTypes: true, lineComments: ["#"],
        strings: [doubleQuoted, singleQuoted, .init(open: "`", close: "`")],
        ruby: true)

    static let go = LanguageSpec(
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
                   "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
                   "struct", "switch", "type", "var", "true", "false", "nil", "iota"],
        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16",
                "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any"],
        lineComments: ["//"], blockComment: cBlock,
        strings: [.init(open: "`", close: "`", escapes: false, multiline: true), doubleQuoted, singleQuoted])

    static let rust = LanguageSpec(
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
                   "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                   "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use",
                   "where", "while", "union"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64",
                "bool", "char", "str"],
        capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock, nestedBlockComments: true,
        strings: [.init(open: "r#\"", close: "\"#", escapes: false, multiline: true),
                  .init(open: "r\"", close: "\"", escapes: false, multiline: true),
                  .init(open: "\"", close: "\"", multiline: true)],
        stringPrefixes: ["b"], rust: true)

    private static let cKeywords: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern",
        "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed",
        "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "NULL",
        "true", "false", "bool"]
    private static let cTypes: Set<String> = ["size_t", "ssize_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t",
                                              "uint16_t", "uint32_t", "uint64_t", "uintptr_t", "FILE"]

    static let c = LanguageSpec(
        keywords: cKeywords, types: cTypes, lineComments: ["//"], blockComment: cBlock,
        strings: [doubleQuoted, singleQuoted], directives: .lineStart)

    static let cpp = LanguageSpec(
        keywords: cKeywords.union(["alignas", "alignof", "and", "catch", "class", "constexpr", "consteval", "decltype",
                                   "delete", "explicit", "export", "friend", "mutable", "namespace", "new", "noexcept",
                                   "nullptr", "operator", "or", "not", "private", "protected", "public", "template",
                                   "this", "throw", "try", "typename", "using", "virtual", "override", "final",
                                   "co_await", "co_return", "co_yield", "concept", "requires", "static_cast",
                                   "dynamic_cast", "reinterpret_cast", "const_cast"]),
        types: cTypes.union(["string", "vector", "map", "set", "unique_ptr", "shared_ptr", "std"]),
        lineComments: ["//"], blockComment: cBlock,
        strings: [.init(open: "R\"(", close: ")\"", escapes: false, multiline: true), doubleQuoted, singleQuoted],
        directives: .lineStart)

    static let objectiveC = LanguageSpec(
        keywords: cKeywords.union(["self", "super", "nil", "Nil", "YES", "NO", "id", "instancetype", "SEL", "BOOL",
                                   "nonatomic", "atomic", "strong", "weak", "copy", "assign", "readonly", "readwrite",
                                   "nullable", "nonnull", "__block", "__weak", "IBAction", "IBOutlet"]),
        types: cTypes, capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock,
        strings: [doubleQuoted, singleQuoted], stringPrefixes: ["@"], attributePrefix: true, directives: .lineStart)

    static let java = LanguageSpec(
        keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
                   "continue", "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for",
                   "goto", "if", "implements", "import", "instanceof", "int", "interface", "long", "native", "new",
                   "package", "private", "protected", "public", "record", "return", "short", "static", "strictfp",
                   "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "var", "void",
                   "volatile", "while", "yield", "true", "false", "null", "sealed", "permits"],
        capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock,
        strings: [.init(open: "\"\"\"", close: "\"\"\"", multiline: true), doubleQuoted, singleQuoted],
        attributePrefix: true)

    static let kotlin = LanguageSpec(
        keywords: ["abstract", "annotation", "as", "break", "by", "catch", "class", "companion", "const", "constructor",
                   "continue", "crossinline", "data", "do", "else", "enum", "external", "false", "final", "finally",
                   "for", "fun", "get", "if", "import", "in", "infix", "init", "inline", "inner", "interface",
                   "internal", "is", "lateinit", "noinline", "null", "object", "open", "operator", "out", "override",
                   "package", "private", "protected", "public", "reified", "return", "sealed", "set", "super",
                   "suspend", "this", "throw", "true", "try", "typealias", "val", "var", "vararg", "when", "where",
                   "while", "value"],
        capitalizedTypes: true, lineComments: ["//"], blockComment: cBlock, nestedBlockComments: true,
        strings: [.init(open: "\"\"\"", close: "\"\"\"", escapes: false, multiline: true), doubleQuoted, singleQuoted],
        attributePrefix: true)

    static let sql = LanguageSpec(
        keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete",
                   "create", "table", "drop", "alter", "add", "column", "index", "view", "join", "inner", "left",
                   "right", "outer", "full", "cross", "on", "as", "group", "by", "order", "having", "limit", "offset",
                   "union", "all", "distinct", "case", "when", "then", "else", "end", "null", "is", "in", "like",
                   "between", "exists", "primary", "key", "foreign", "references", "default", "unique", "check",
                   "constraint", "asc", "desc", "with", "returning", "begin", "commit", "rollback", "transaction",
                   "if", "true", "false", "integer", "int", "text", "varchar", "char", "boolean", "date", "timestamp",
                   "real", "numeric", "decimal", "serial", "bigint", "blob", "autoincrement", "cascade", "using"],
        caseInsensitiveKeywords: true, lineComments: ["--"], blockComment: cBlock,
        strings: [.init(open: "'", close: "'", escapes: false, multiline: true)])
}
