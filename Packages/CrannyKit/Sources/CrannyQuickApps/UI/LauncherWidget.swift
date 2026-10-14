// CrannyQuickApps/UI/LauncherWidget.swift — the Quick Apps & Shortcuts widget (DESIGN.md §7.3, §6.7): 1–6 cells,
// two tiles per cell column (default 2 cells = 4 tiles). The shell draws the card; this draws its content.
import CrannyCore
import Foundation
import SwiftUI

final class LauncherWidget: NookWidget {
    let model: QuickAppsModel
    init(model: QuickAppsModel) { self.model = model }

    let id: WidgetID = .quickApps
    var title: String {
        String(localized: "Quick Apps", bundle: .module, comment: "Quick Apps: widget name (widget library, VoiceOver container)")
    }
    let symbol = "app.dashed"
    var summary: String {
        String(localized: "Open apps and run shortcuts in one click", bundle: .module, comment: "Widget library: Quick Apps description")
    }
    let sizes = WidgetSizes(minimum: 1, preferred: 2, maximum: 6)

    func makeBody(context: WidgetContext) -> some View { LauncherView(model: model, context: context) }
    func makeOptions() -> some View { LauncherOptions(model: model) }
}

/// The widget's options popover (the card's ⋯ menu, Settings ▸ Layout & Widgets): system controls.
struct LauncherOptions: View {
    let model: QuickAppsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Toggle(isOn: model.settings.binding(QuickAppsSettings.showsLabels)) {
                Text("Show names under tiles", bundle: .module, comment: "Quick Apps: option toggle (widget options, Settings ▸ Shortcuts)")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Divider()
            Button { model.isEditing = true } label: {
                Text("Edit Tiles", bundle: .module, comment: "Quick Apps: menu item, enter edit mode (remove, reorder, add)")
            }
            Button { model.openSettings() } label: {
                Text("Quick Apps Settings…", bundle: .module, comment: "Quick Apps: opens Settings ▸ Shortcuts")
            }
        }
        .buttonStyle(.link)
        .padding(Space.l)
        .frame(minWidth: 220, alignment: .leading)
    }
}

#Preview("Widget options") {
    LauncherOptions(model: QuickAppsPreview.model())
}
