// CrannyNotchUI/Compact/CompactView.swift — the primary live activity in the wings around the camera
// (DESIGN.md §9.1). WP0 skeleton: leading and trailing slots. WP12 adds the floating-island middle label
// (it needs a label-aware `NotchSceneModel.geometry`), the satellite, the progress rim and matched geometry.
import CrannyCore
import SwiftUI

struct CompactView: View {
    @Environment(\.cranny) private var theme
    let model: NotchSceneModel
    let registry: ModuleRegistry
    let actions: NotchUIActions

    var body: some View {
        if let id = model.primary, let activity = model.activity(id, in: registry) {
            CompactRow(layout: model.layout, activity: activity)
                .contentShape(Rectangle())
                .onTapGesture { actions.activityTapped(id) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: activity.accessibilityLabel))
                .accessibilityValue(Text(verbatim: activity.accessibilityValue ?? ""))
                .accessibilityAddTraits(.isButton)
                .transition(.crannySlot(edge: .leading, reduceMotion: theme.reduceMotion))
        }
    }
}

/// One compact row; also the top row of the peek presentation.
struct CompactRow: View {
    @Environment(\.cranny) private var theme
    let layout: NotchLayout
    let activity: any LiveActivity

    var body: some View {
        CompactSlots(layout: layout, slot: activity.slot,
                     leading: { activity.view(for: .compactLeading) },
                     center: { EmptyView() },
                     trailing: { activity.view(for: .compactTrailing) })
            .foregroundStyle(theme.palette.label)
    }
}

#Preview("Compact · sample activity") {
    let (model, registry) = previewScene(.compact)
    CompactView(model: model, registry: registry, actions: NotchUIActions())
        .frame(width: model.layout.compact(model.primarySlot).outerWidth)
        .background(.black)
        .crannyThemeRoot(CrannyTheme())
}
