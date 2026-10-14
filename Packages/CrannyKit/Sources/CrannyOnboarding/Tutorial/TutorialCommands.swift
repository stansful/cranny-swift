// CrannyOnboarding/Tutorial/TutorialCommands.swift — the tour's keyboard way out (DESIGN.md §16: every action has
// a key path). The bubble's "Skip tutorial" lives in a panel that never becomes key, and Esc belongs to the notch (it
// is also step 5's action), so while a tour runs ⌘K offers "Skip tutorial": ⌃⌥N, ⌘K, type "skip", ↩. In-memory
// filtering only (the palette asks on every keystroke).
import CrannyCore
import Foundation

final class TutorialCommands: PaletteCommandProvider {
    private weak var tutorial: TutorialController?

    init(tutorial: TutorialController) { self.tutorial = tutorial }

    func commands(matching query: String) -> [PaletteCommand] {
        guard let tutorial, tutorial.isRunning else { return [] }
        let command = PaletteCommand(id: "onboarding.tutorial.skip", title: TutorialController.skipTitle, kind: "Cranny",
                                     symbol: "cursorarrow.motionlines", keywords: Self.keywords) { [weak tutorial] in
            tutorial?.stop()
        }
        return Self.matches(command, query: query) ? [command] : []
    }

    /// Every word of the query appears in the title, the kind or a keyword (case- and diacritic-insensitive).
    static func matches(_ command: PaletteCommand, query: String) -> Bool {
        let haystack = ([command.title, command.kind] + command.keywords).joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.localizedStandardContains($0) }
    }

    private static var keywords: [String] {
        String(localized: "tutorial, tour, stop, end, skip", bundle: .module,
               comment: "⌘K: search words for Skip tutorial while the tutorial runs, comma-separated")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
