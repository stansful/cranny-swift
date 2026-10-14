// "Automatic" language: extension, shebang, fence/heading, then phrase scoring; nil when unsure.
import Testing
@testable import CrannyNotes

@Suite("Language detection") struct LanguageDetectorTests {
    @Test func fileExtensionWins() {
        #expect(LanguageDetector.detect(title: "deploy.md", text: "def f(): pass") == .markdown)
        #expect(LanguageDetector.detect(title: "App.swift", text: "") == .swift)
        #expect(LanguageDetector.detect(title: "build.SH", text: "") == .shell)
        #expect(LanguageDetector.detect(title: "Info.plist", text: "") == .html)
        #expect(LanguageDetector.detect(title: "main.rs", text: "") == .rust)
        #expect(LanguageDetector.detect(title: "styles.scss", text: "") == .css)
        #expect(CodeLanguage(fileName: ".zshrc") == nil)                        // a dot file has no extension
        #expect(CodeLanguage(fileName: "Shopping list") == nil)
    }

    @Test func shebang() {
        #expect(LanguageDetector.shebang("#!/usr/bin/env python3\nprint(1)") == .python)
        #expect(LanguageDetector.shebang("#!/bin/bash -e") == .shell)
        #expect(LanguageDetector.shebang("#!/bin/zsh") == .shell)
        #expect(LanguageDetector.shebang("#!/usr/bin/env -S node --flag") == .javascript)
        #expect(LanguageDetector.shebang("#!/usr/bin/swift") == .swift)
        #expect(LanguageDetector.shebang("#!/usr/bin/perl") == nil)
        #expect(LanguageDetector.shebang("# not a shebang") == nil)
    }

    @Test func markdownByFenceOrHeading() {
        #expect(LanguageDetector.detect(title: "Untitled", text: "```swift\nlet x = 1\n```") == .markdown)
        #expect(LanguageDetector.detect(title: "Untitled", text: "Intro\n\n## Steps\n1. a") == .markdown)
        #expect(LanguageDetector.detect(title: "Untitled", text: "- [ ] milk\n- [x] eggs") == .markdown)
    }

    @Test func phraseScoring() {
        #expect(LanguageDetector.detect(title: "a", text: "import SwiftUI\nstruct A: View { var body: some View { Text(\"x\") } }") == .swift)
        #expect(LanguageDetector.detect(title: "a", text: "def main():\n    print('x')\n\nif __name__ == '__main__':\n    main()") == .python)
        #expect(LanguageDetector.detect(title: "a", text: "package main\n\nfunc main() {\n\tx := 1\n\tfmt.Println(x)\n}") == .go)
        #expect(LanguageDetector.detect(title: "a", text: "SELECT id FROM users WHERE name = 'a' ORDER BY id;") == .sql)
        #expect(LanguageDetector.detect(title: "a", text: "const a = require('x');\nconsole.log(a);") == .javascript)
        #expect(LanguageDetector.detect(title: "a", text: "#include <stdio.h>\nint main(void) { printf(\"hi\"); }") == .c)
        #expect(LanguageDetector.detect(title: "a", text: "<!DOCTYPE html>\n<html><body></body></html>") == .html)
        #expect(LanguageDetector.detect(title: "a", text: ".card {\n  margin: 0;\n  font-size: 12px;\n}") == .css)
        #expect(LanguageDetector.detect(title: "a", text: "fn main() {\n    let mut v = Vec::new();\n    println!(\"{}\", 1);\n}") == .rust)
        #expect(LanguageDetector.detect(title: "a", text: "brew install node\ncd ~/src && git pull\necho done") == .shell)
    }

    @Test func dataShapes() {
        #expect(LanguageDetector.detect(title: "a", text: "{\n  \"name\": \"x\",\n  \"n\": 1\n}") == .json)
        #expect(LanguageDetector.detect(title: "a", text: "[1, 2, 3]") == .json)
        #expect(LanguageDetector.detect(title: "a", text: "name: cranny\nversion: 1\nitems:\n  - a\n  - b") == .yaml)
    }

    @Test func unsureMeansNil() {
        #expect(LanguageDetector.detect(title: "Untitled", text: "") == nil)
        #expect(LanguageDetector.detect(title: "Untitled", text: "Buy milk and call Ana about the trip.") == nil)
        #expect(LanguageDetector.detect(title: "Untitled", text: "let") == nil)
    }

    @Test func fenceAliases() {
        #expect(CodeLanguage(alias: "Swift") == .swift)
        #expect(CodeLanguage(alias: "c++") == .cpp)
        #expect(CodeLanguage(alias: "yml") == .yaml)
        #expect(CodeLanguage(alias: "objective-c") == .objectiveC)
        #expect(CodeLanguage(alias: "brainfuck") == nil)
        #expect(CodeLanguage(alias: "") == nil)
    }
}
