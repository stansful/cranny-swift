// CrannyQuickApps/UI/LauncherKeyboardShortcuts.swift — ⌥1–⌥9 open the first nine tiles from anywhere in the
// open panel while it is key (DESIGN.md §7.3, §6.5). Key equivalents of invisible buttons: they need no focus,
// draw nothing (alpha-0 pixels stay click-through) and exist only while the launcher is on screen.
import CrannyCore
import SwiftUI

struct LauncherKeyboardShortcuts: View {
    let model: QuickAppsModel
    let tiles: [LauncherTile]

    var body: some View {
        ZStack {
            ForEach(Array(tiles.prefix(9).enumerated()), id: \.element.id) { index, tile in
                Button { if !model.isEditing { model.activate(tile) } } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)          // VoiceOver gets the shortcut as each tile's hint instead
    }
}

#Preview("Keyboard shortcuts (invisible)") {
    // Draws nothing by design: the preview only proves it lays out at zero size next to the launcher.
    QuickAppsPreview.widget(cells: 2)
        .background(LauncherKeyboardShortcuts(model: QuickAppsPreview.model(), tiles: QuickAppsPreview.model().tiles))
}
