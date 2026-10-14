// CrannyNotes/UI/DeleteConfirmationView.swift — "Delete ‹title›?" inside the card, in place of the editor (no sheet
// over the notch): one line, why, Cancel and a `danger` Delete (DESIGN.md §2.1: danger = destructive).
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
                    .buttonStyle(CrannyChipButtonStyle())
                    .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
                    .contentShape(Rectangle())
                Button(role: .destructive) { model.confirmDelete() } label: { Text(NotesStrings.delete) }
                    .buttonStyle(CrannyChipButtonStyle(tint: p.danger, prominent: true))
                    .frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}
