// CrannyNotes/UI/NoteSidebar.swift — the note list beside the editor at 6 cells and wider, and in focus mode
// (DESIGN.md §6.7): one cell wide, 24-pt rows, the current note on `controlPressed`, hover on `control`.
import CrannyCore
import SwiftUI

struct NoteSidebar: View {
    let model: NotesModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                ForEach(model.entries) { entry in
                    SidebarRow(title: entry.title, isSelected: entry.id == model.selectedID) { model.select(entry.id) }
                }
            }
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(NotesStrings.notesList))
    }
}

private struct SidebarRow: View {
    @Environment(\.cranny) private var theme
    @State private var isHovered = false
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            Text(title)
                .crannyFont(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? p.label : p.secondaryLabel)
                .padding(.horizontal, Space.s)
                .frame(maxWidth: .infinity, minHeight: HitTarget.nook.height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(isSelected ? p.controlPressed : isHovered ? p.control : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(theme.animation(.hover), value: isHovered)
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Note list sidebar") {
    NotesPreviewFrame(width: 120) { NoteSidebar(model: NotesModel.preview()).frame(height: 96) }
}
