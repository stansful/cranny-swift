// CrannyNotchUI/Nook/HUDHeaderOverlay.swift — the HUD while the panel is open (DESIGN.md §10, ARCHITECTURE.md
// §4.11): its leading and trailing views take the header row, left and right of the camera, in place of the
// tabs and actions, for the HUD's lifetime. The open shape never changes; the swap is `contentSwap`.
import CrannyCore
import SwiftUI

struct HUDHeaderOverlay: View {
    @Environment(\.cranny) private var theme
    let id: ActivityID
    let activity: any LiveActivity
    let layout: NotchLayout
    let actions: NotchUIActions

    var body: some View {
        let u = layout.u
        let content = SlotWidth.wide.points(unit: u) - 20 * u          // − 12u outer − 8u gap (DESIGN.md §3.3)
        HStack(spacing: 8 * u) {
            activity.view(for: .compactLeading)
                .frame(width: content, alignment: .trailing)
            Color.clear.frame(width: layout.middle())                    // the camera; content sits 8u beside it
            activity.view(for: .compactTrailing)
                .frame(width: content, alignment: .leading)
        }
        .foregroundStyle(theme.palette.label)
        .frame(maxWidth: .infinity)
        .activityAccessibility(activity, id: id, open: nil, dismiss: nil)
    }
}

#Preview("HUD in the open header") {
    let (model, registry) = previewScene(.open, hudInHeader: true)
    NotchCanvasView(model: model, registry: registry)
        .frame(width: model.layout.canvasSize.width, height: 240)
        .background(Color(white: 0.25))
}
