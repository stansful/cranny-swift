// CrannyNotes/UI/DeleteConfirmationView.swift — "Delete ‹title›?" inside the card, in place of the editor (no sheet
// over the notch): one line, why, Cancel (Esc) and a `danger` Delete (Return; DESIGN.md §2.1: danger = destructive).
// Either way the caret goes back to a note afterwards.
import CrannyCore
import SwiftUI

struct DeleteConfirmationView: View {
    @Environment(\.cranny) private var theme
    let model: NotesModel
    let title: String

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(NotesStrings.deleteQuestion(title))
                .crannyFont(.body)
                .foregroundStyle(p.label)
                .lineLimit(2)
            Text(NotesStrings.deleteDetail)
                .crannyFont(.callout)
                .foregroundStyle(p.secondaryLabel)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: Space.s) {
                Spacer(minLength: 0)
                Button { model.cancelDelete() } label: { Text(NotesStrings.cancel) }
                    .keyboardShortcut(.cancelAction)                            // Esc
                    .buttonStyle(CrannyChipButtonStyle())
                Button { model.confirmDelete() } label: { Text(NotesStrings.delete) }
                    .keyboardShortcut(.defaultAction)                           // Return: the user chose Delete… already
                    .buttonStyle(CrannyChipButtonStyle(tint: p.danger, prominent: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Delete confirmation") {
    NotesPreviewFrame(width: 224) {
        DeleteConfirmationView(model: NotesModel.preview(), title: "deploy.md").frame(height: 68)
    }
}
