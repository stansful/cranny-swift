// CrannyNotes/UI/NotesPreviewSupport.swift — sample notes and a card host for this target's #Preview blocks
// (ARCHITECTURE.md §9.4): `CrannyServices.preview()` (temporary paths, in-memory settings), black, themed.
import CrannyCore
import SwiftUI

/// Sample notes with original content.
enum NotesSample {
    case deploy, groceries

    var note: Note {
        switch self {
        case .deploy:
            Note(title: "deploy.md", text: """
                ## Release
                let build = "1.4.2"
                retry(3) // flaky CI
                - [ ] tag `v1.4.2`
                """, mode: .code)
        case .groceries:
            Note(title: "Weekend", text: "Oat milk, lemons, basil\nCall the bike shop before noon\nReturn the library books", mode: .plain)
        }
    }
}

/// A card of `cells` with a model holding `sample` (or no notes), already loaded.
struct NotesPreviewHost: View {
    let cells: Int
    let sample: NotesSample?
    @State private var model: NotesModel

    init(cells: Int, sample: NotesSample?) {
        self.cells = cells
        self.sample = sample
        let services = CrannyServices.preview()
        let model = NotesModel(settings: services.settings, notch: services.notch, store: NotesStore(paths: services.paths))
        model.adoptLoadedNotes(sample.map { [$0.note, NotesSample.groceries.note] } ?? [])
        _model = State(initialValue: model)
    }

    var body: some View {
        let theme = CrannyTheme()
        let grid = theme.grid
        let inset = grid.density.cardPadding
        NotesWidgetView(model: model, settings: model.settings, context: WidgetContext(
            cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset)))
            .crannyCard(cells: cells)
            .padding()
            .background(.black)
            .crannyThemeRoot(theme)
    }
}
