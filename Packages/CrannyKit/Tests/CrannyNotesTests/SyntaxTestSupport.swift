// Helpers for the highlighter tests: tokens as (kind, text) pairs and a seeded random generator.
import Foundation
@testable import CrannyNotes

struct Highlight: Equatable, CustomStringConvertible {
    let kind: SyntaxKind
    let text: String
    init(_ kind: SyntaxKind, _ text: String) { self.kind = kind; self.text = text }
    var description: String { "\(kind.rawValue)(\(text))" }
}

func highlights(_ text: String, _ language: CodeLanguage?) -> [Highlight] {
    let ns = text as NSString
    return SyntaxHighlighter.tokens(in: text, language: language).map { Highlight($0.kind, ns.substring(with: $0.range)) }
}

extension Array where Element == Highlight {
    func has(_ kind: SyntaxKind, _ text: String) -> Bool { contains(Highlight(kind, text)) }
    func kind(of text: String) -> SyntaxKind? { first { $0.text == text }?.kind }
    /// Nothing whose text contains `fragment` was coloured.
    func leavesPlain(_ fragment: String) -> Bool { !contains { $0.text.contains(fragment) } }
}

/// Deterministic pseudo-random numbers (SplitMix64) so property tests reproduce.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One sample per language, used by the invariant and incremental-restyling tests.
nonisolated let languageSamples: [(CodeLanguage?, String)] = [
    (.markdown, "# Title\n\nSome *emphasis* and **strong** text with `code` and [a link](https://example.com).\n\n```swift\nlet x = 1 // one\n```\n> quote\n- item\n1. first\n"),
    (.swift, "import SwiftUI\n\n@MainActor struct Card: View {\n    let title = \"Hi \\(name)\" // greeting\n    var body: some View { Text(title).padding(12) }\n    /* block /* nested */ still */\n    let raw = #\"a \"quoted\" b\"#\n}\n"),
    (.python, "#!/usr/bin/env python3\n@decorator\ndef greet(name: str) -> None:\n    \"\"\"Doc\nstring\"\"\"\n    print(f'hi {name}', 0x1F, 3.5e-2)  # comment\n"),
    (.javascript, "const add = (a, b) => a + b; // sum\nfunction main() { console.log(`total ${add(1, 2)}`, 'x', 0.5); }\n/* block */\n"),
    (.typescript, "interface User { name: string; age: number }\nexport type Id = string;\nconst u: User = { name: \"Ana\", age: 30 };\n"),
    (.json, "{\n  \"name\": \"cranny\",\n  \"version\": 1.2,\n  \"tags\": [\"notch\", true, null],\n  // comment\n  \"nested\": { \"x\": -3e2 }\n}\n"),
    (.shell, "#!/bin/zsh\n# deploy\nexport PATH=\"$HOME/bin:$PATH\"\nif [ -n \"${NAME}\" ]; then\n  echo 'hi' $1 a#b\nfi\n"),
    (.ruby, "require 'json'\nclass Greeter\n  attr_accessor :name\n  def greet?\n    puts \"hi #{@name}\" # say\n  end\nend\n"),
    (.go, "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tx := 42 // answer\n\tfmt.Println(`raw`, x, 'r')\n}\n"),
    (.rust, "use std::io;\n#[derive(Debug)]\nfn main<'a>(s: &'a str) -> u32 {\n    let mut c = 'x';\n    println!(\"{}\", r#\"raw \"s\"\"#);\n    0xFF_u32 // hex\n}\n"),
    (.c, "#include <stdio.h>\n#define N 10\nint main(void) {\n    printf(\"%d\\n\", N); /* print */\n    return 0;\n}\n"),
    (.cpp, "#include <iostream>\nnamespace app {\ntemplate<typename T> T twice(T v) { return v * 2; }\n}\nint main() { std::cout << R\"(raw)\" << nullptr; }\n"),
    (.objectiveC, "#import <Foundation/Foundation.h>\n@interface Note : NSObject\n@property (nonatomic, copy) NSString *title;\n@end\nNSString *s = @\"hi\"; // c\n"),
    (.java, "package app;\n@Override\npublic class Main {\n    public static void main(String[] args) { System.out.println(\"hi\" + 1L); }\n}\n"),
    (.kotlin, "data class User(val name: String)\nfun main() {\n    val u = User(\"Ana\")\n    println(\"\"\"raw $u\"\"\") // c\n}\n"),
    (.html, "<!DOCTYPE html>\n<html lang=\"en\">\n<!-- comment -->\n<body class=main>\n<p>Hi &amp; bye</p>\n<script>const a = 1;</script>\n<style>p { color: #fff; }</style>\n</body>\n</html>\n"),
    (.css, "/* theme */\n@media (max-width: 600px) {\n  .card > p:hover { color: #1e2026; margin: 0 -2px 1.5em; }\n}\nbody { font-family: \"SF Pro\", sans-serif !important; background: url(a.png); }\n"),
    (.sql, "-- users\nSELECT name, COUNT(*) FROM users WHERE age > 21 AND city = 'Riga' GROUP BY name;\n/* done */\n"),
    (.yaml, "---\n# config\nname: cranny\nversion: 1.2\nenabled: true\nlist:\n  - one\n  - \"two\"\nanchor: &base\n  x: 1\ntext: |\n  line one: not a key\n  line two\nnext: ~\n"),
    (nil, "value = \"text\" // comment\ncount: 42 /* block */ don't break\n"),
]
