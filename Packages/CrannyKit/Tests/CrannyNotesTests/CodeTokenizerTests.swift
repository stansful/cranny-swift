// Highlighter tests per language (ARCHITECTURE.md §10.6 acceptance: "highlighter tests per language").
import Foundation
import Testing
@testable import CrannyNotes

@Suite("Code languages") struct CodeTokenizerTests {
    @Test func swift() {
        let h = highlights(languageSamples[1].1, .swift)
        #expect(h.has(.keyword, "import"))
        #expect(h.has(.type, "SwiftUI"))
        #expect(h.has(.keyword, "@MainActor"))
        #expect(h.has(.keyword, "struct"))
        #expect(h.has(.type, "Card"))
        #expect(h.has(.string, "\"Hi \\(name)\""))
        #expect(h.has(.comment, "// greeting"))
        #expect(h.has(.function, "Text") == false)                              // capitalised → type, not function
        #expect(h.has(.type, "Text"))
        #expect(h.has(.function, "padding"))
        #expect(h.has(.number, "12"))
        #expect(h.has(.comment, "/* block /* nested */ still */"))             // nested block comments
        #expect(h.has(.string, "#\"a \"quoted\" b\"#"))                        // raw string
        #expect(highlights("#if DEBUG\nlet a = 1..<5\n#endif", .swift).has(.keyword, "#if"))
        #expect(highlights("let r = 1..<5", .swift).has(.number, "1"))
        #expect(highlights("let s = \"\"\"\nmulti\n\"\"\"", .swift).has(.string, "\"\"\"\nmulti\n\"\"\""))
    }

    @Test func python() {
        let h = highlights(languageSamples[2].1, .python)
        #expect(h.has(.comment, "#!/usr/bin/env python3"))
        #expect(h.has(.keyword, "@decorator"))
        #expect(h.has(.keyword, "def"))
        #expect(h.has(.function, "greet"))
        #expect(h.has(.type, "str"))
        #expect(h.has(.keyword, "None"))
        #expect(h.has(.string, "\"\"\"Doc\nstring\"\"\""))
        #expect(h.has(.string, "f'hi {name}'"))                                 // prefixed string
        #expect(h.has(.number, "0x1F"))
        #expect(h.has(.number, "3.5e-2"))
        #expect(h.has(.comment, "# comment"))
    }

    @Test func javaScriptAndTypeScript() {
        let js = highlights(languageSamples[3].1, .javascript)
        #expect(js.has(.keyword, "const"))
        #expect(js.has(.comment, "// sum"))
        #expect(js.has(.keyword, "function"))
        #expect(js.has(.function, "main"))
        #expect(js.has(.string, "`total ${add(1, 2)}`"))
        #expect(js.has(.string, "'x'"))
        #expect(js.has(.number, "0.5"))
        #expect(js.has(.comment, "/* block */"))
        let ts = highlights(languageSamples[4].1, .typescript)
        #expect(ts.has(.keyword, "interface"))
        #expect(ts.has(.type, "User"))
        #expect(ts.has(.type, "string"))
        #expect(ts.has(.keyword, "type"))
        #expect(ts.has(.number, "30"))
    }

    @Test func shell() {
        let h = highlights(languageSamples[6].1, .shell)
        #expect(h.has(.comment, "#!/bin/zsh"))
        #expect(h.has(.comment, "# deploy"))
        #expect(h.has(.keyword, "export"))
        #expect(h.has(.string, "\"$HOME/bin:$PATH\""))
        #expect(h.has(.type, "$1"))
        #expect(h.has(.keyword, "then"))
        #expect(h.has(.keyword, "fi"))
        #expect(h.leavesPlain("a#b"))                                           // `#` inside a word is not a comment
        #expect(highlights("echo ${HOME} $USER", .shell).has(.type, "${HOME}"))
    }

    @Test func ruby() {
        let h = highlights(languageSamples[7].1, .ruby)
        #expect(h.has(.keyword, "require"))
        #expect(h.has(.string, "'json'"))
        #expect(h.has(.type, "Greeter"))
        #expect(h.has(.string, ":name"))                                        // symbol
        #expect(h.has(.keyword, "def"))
        #expect(h.has(.keyword, "attr_accessor"))
        #expect(h.has(.keyword, "puts"))
        #expect(h.leavesPlain("greet"))                                         // `greet?` is one plain name
        #expect(highlights("@count = 1", .ruby).has(.type, "@count"))
        #expect(h.has(.comment, "# say"))
        #expect(h.has(.keyword, "end"))
    }

    @Test func go() {
        let h = highlights(languageSamples[8].1, .go)
        #expect(h.has(.keyword, "package"))
        #expect(h.has(.keyword, "func"))
        #expect(h.has(.function, "main"))
        #expect(h.has(.string, "\"fmt\""))
        #expect(h.has(.number, "42"))
        #expect(h.has(.string, "`raw`"))
        #expect(h.has(.string, "'r'"))
        #expect(h.has(.function, "Println"))
    }

    @Test func rust() {
        let h = highlights(languageSamples[9].1, .rust)
        #expect(h.has(.keyword, "use"))
        #expect(h.has(.keyword, "#[derive(Debug)]"))
        #expect(h.has(.keyword, "fn"))
        #expect(h.has(.type, "'a"))                                             // lifetime, not a string
        #expect(h.has(.type, "u32"))
        #expect(h.has(.string, "'x'"))                                          // character
        #expect(h.has(.function, "println!"))                                   // macro
        #expect(h.has(.string, "r#\"raw \"s\"\"#"))
        #expect(h.has(.number, "0xFF_u32"))
    }

    @Test func cFamily() {
        let c = highlights(languageSamples[10].1, .c)
        #expect(c.has(.keyword, "#include"))
        #expect(c.has(.string, "<stdio.h>"))
        #expect(c.has(.keyword, "#define"))
        #expect(c.has(.keyword, "int"))
        #expect(c.has(.function, "printf"))
        #expect(c.has(.string, "\"%d\\n\""))
        #expect(c.has(.comment, "/* print */"))
        let cpp = highlights(languageSamples[11].1, .cpp)
        #expect(cpp.has(.keyword, "namespace"))
        #expect(cpp.has(.keyword, "template"))
        #expect(cpp.has(.string, "R\"(raw)\""))
        #expect(cpp.has(.keyword, "nullptr"))
        let objc = highlights(languageSamples[12].1, .objectiveC)
        #expect(objc.has(.keyword, "#import"))
        #expect(objc.has(.keyword, "@interface"))
        #expect(objc.has(.type, "NSString"))
        #expect(objc.has(.string, "@\"hi\""))
        #expect(objc.has(.keyword, "nonatomic"))
    }

    @Test func javaAndKotlin() {
        let java = highlights(languageSamples[13].1, .java)
        #expect(java.has(.keyword, "@Override"))
        #expect(java.has(.keyword, "public"))
        #expect(java.has(.type, "String"))
        #expect(java.has(.function, "println"))
        #expect(java.has(.number, "1L"))
        let kotlin = highlights(languageSamples[14].1, .kotlin)
        #expect(kotlin.has(.keyword, "data"))
        #expect(kotlin.has(.keyword, "fun"))
        #expect(kotlin.has(.keyword, "val"))
        #expect(kotlin.has(.string, "\"\"\"raw $u\"\"\""))
        #expect(kotlin.has(.comment, "// c"))
    }

    @Test func sql() {
        let h = highlights(languageSamples[17].1, .sql)
        #expect(h.has(.comment, "-- users"))
        #expect(h.has(.keyword, "SELECT"))                                      // case-insensitive keywords
        #expect(h.has(.function, "COUNT"))
        #expect(h.has(.keyword, "FROM"))
        #expect(h.has(.number, "21"))
        #expect(h.has(.string, "'Riga'"))
        #expect(h.has(.comment, "/* done */"))
        #expect(highlights("select * from t", .sql).has(.keyword, "select"))
    }

    @Test func genericCodeIgnoresApostrophes() {
        let h = highlights(languageSamples.last!.1, nil)
        #expect(h.has(.string, "\"text\""))
        #expect(h.has(.comment, "// comment"))
        #expect(h.has(.number, "42"))
        #expect(h.has(.comment, "/* block */"))
        #expect(h.leavesPlain("don't"))
    }

    @Test func unterminatedConstructsStopSafely() {
        #expect(highlights("let s = \"open\nnext", .swift).has(.string, "\"open"))  // single-line string stops at the newline
        #expect(highlights("/* never closed", .c).has(.comment, "/* never closed"))
        #expect(highlights("x = '''open", .python).has(.string, "'''open"))
    }

    @Test func nonASCIIIdentifiersStayWhole() {
        let h = highlights("let имя = \"Привет\" // комментарий", .swift)
        #expect(h.has(.string, "\"Привет\""))
        #expect(h.has(.comment, "// комментарий"))
        #expect(h.leavesPlain("имя"))
    }
}
