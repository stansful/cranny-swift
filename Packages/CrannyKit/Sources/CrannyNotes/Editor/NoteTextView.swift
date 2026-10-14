// CrannyNotes/Editor/NoteTextView.swift — the editor as a SwiftUI view: an `NSTextView` (TextKit 2) in an
// `NSViewRepresentable` (ARCHITECTURE.md §10.6). Reads the theme and the model; `EditorCoordinator` does the work.
import AppKit
import CrannyCore
import SwiftUI

struct NoteTextView: NSViewRepresentable {
    @Environment(\.cranny) private var theme
    let model: NotesModel
    let entry: NotesModel.Entry
    let typingEffect: Bool
    let showsLineNumbers: Bool
    /// Read by the parent's body (observation-tracked), so a change re-runs `updateNSView`.
    let focusRequested: Bool
    let externalRevision: Int

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeView() }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(EditorConfiguration(
            noteID: entry.id, entry: entry, style: EditorStyle(theme: theme, mode: entry.mode),
            // DESIGN.md §7.5: off under Reduce Motion and the Instant motion personality.
            typingEffect: typingEffect && !theme.reduceMotion && theme.motion != .instant,
            showsLineNumbers: showsLineNumbers, focusRequested: focusRequested, externalRevision: externalRevision))
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: EditorCoordinator) {
        coordinator.dismantle()
    }
}
