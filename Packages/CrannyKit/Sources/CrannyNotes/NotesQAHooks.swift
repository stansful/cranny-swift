// CrannyNotes/NotesQAHooks.swift — DEBUG-only visual QA for states that otherwise need clicks or typing
// (docs/CONTRIBUTING.md "Visual QA hooks"). Comma-separated, applied once after the notes are loaded:
//
//   --qa-notes select:2      show the 3rd note          --qa-notes delete     the delete confirmation
//   --qa-notes rename        the inline rename field    --qa-notes capture    type-to-capture "Hel"
//   --qa-notes saveFailed    the save warning           --qa-notes typing     a frozen typing effect
//   --qa-notes focus         ask the shell for focus mode
//
// No input is synthesized; the hooks call the same model methods the controls call. Compiled out of Release.
#if DEBUG
import CrannyCore
import Foundation

enum NotesQAHooks {
    /// The raw `--qa-notes` actions of this process (tests may set them for offscreen snapshots).
    static var actions: [String] = {
        guard let value = LaunchArguments.current.value(after: "--qa-notes") else { return [] }
        return value.split(separator: ",").map(String.init)
    }()

    /// The editor draws the typing effect frozen mid-way on the last characters (checks rendering attributes).
    static var freezesTypingEffect: Bool { actions.contains("typing") }

    static func apply(to model: NotesModel) {
        for action in actions {
            switch action {
            case let a where a.hasPrefix("select:"):
                if let n = Int(a.dropFirst(7)), model.entries.indices.contains(n) { model.select(model.entries[n].id) }
            case "delete": model.requestDelete()
            case "rename": model.beginRename()
            case "capture": _ = model.capture("Hel")
            case "saveFailed": model.saveFailed = true
            case "focus": model.toggleFocusMode()
            default: break
            }
        }
    }
}
#endif
