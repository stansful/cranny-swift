// CrannyNotes/UI/NotesOptionsView.swift — the Notes widget's options (DESIGN.md §11.1, Layout & Widgets: "Notes
// typing effect and default mode"), shown in a popover from Settings and from the card's ⋯ menu. System controls
// and text styles (Settings conventions, DESIGN.md §11.3); settings apply instantly.
import CrannyCore
import SwiftUI

struct NotesOptionsView: View {
    let settings: SettingsStore

    var body: some View {
        Form {
            Toggle(isOn: settings.binding(CoreSettings.typingEffect)) {
                Text(NotesStrings.typingEffect)
                Text(NotesStrings.typingEffectFootnote)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Picker(selection: settings.binding(NotesSettings.defaultMode)) {
                Text(NotesStrings.plainText).tag(NoteMode.plain)
                Text(NotesStrings.code).tag(NoteMode.code)
            } label: {
                Text(NotesStrings.newNotes)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Notes options") {
    NotesOptionsView(settings: CrannyServices.preview().settings)
        .frame(width: 360)
}
