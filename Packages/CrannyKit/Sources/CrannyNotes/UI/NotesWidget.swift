// CrannyNotes/UI/NotesWidget.swift — the Notes widget's registration (DESIGN.md §6.7, §7.5): 3–8 cells, 4 by
// default; content only (NotchUI draws the card, the ⋯ menu and the VoiceOver container named "Notes").
import CrannyCore
import SwiftUI

final class NotesWidget: NookWidget {
    let model: NotesModel
    let settings: SettingsStore

    init(model: NotesModel, settings: SettingsStore) { self.model = model; self.settings = settings }

    let id: WidgetID = .notes
    var title: String { NotesStrings.notes }
    let symbol = "note.text"
    var summary: String { NotesStrings.summary }
    let sizes = WidgetSizes(minimum: 3, preferred: 4, maximum: 8)

    func makeBody(context: WidgetContext) -> some View {
        NotesWidgetView(model: model, settings: settings, context: context)
    }

    /// Layout & Widgets ▸ Notes options and the card's ⋯ menu: typing effect and the mode of new notes.
    func makeOptions() -> some View { NotesOptionsView(settings: settings) }
}
