// Views use tokens only (ARCHITECTURE.md §9.4, DESIGN.md §2.0 rule 1): no literal glyph fonts, colours or
// animations in NotchUI's views. Literals live in Core's tables or in NotchUITokens.swift. #Preview blocks, the
// preview sample data and the DEBUG QA hooks are exempt.
import Foundation
import Testing

@Suite("Tokens only (source lint)") struct TokenLintTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CrannyNotchUI")
    private static let exempt: Set<String> = ["NotchUITokens.swift", "PreviewSupport.swift", "PreviewGallery.swift",
                                              "NotchUIQAHooks.swift"]     // DEBUG QA: a grey desktop stand-in
    private static let literals = [".font(.system(", "Color.white.opacity(", "Color(white:", "withAnimation(.",
                                   ".animation(.easeIn", ".animation(.easeOut", ".animation(.spring", ".animation(.linear"]

    @Test func viewsUseTokens() throws {
        let files = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !Self.exempt.contains($0.lastPathComponent) }
        #expect(files.count > 20)
        var hits: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = text.components(separatedBy: "#Preview(").first ?? text          // previews come last
            for (number, line) in code.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") else { continue }
                for literal in Self.literals where line.contains(literal) {
                    hits.append("\(file.lastPathComponent):\(number + 1): \(literal)")
                }
            }
        }
        #expect(hits.isEmpty, "\(hits)")
    }
}
