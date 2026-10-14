// CrannyHUD/UI/HUDPreviewSupport.swift — the HUD drawn the way the shell draws a compact activity
// (`NotchSurface` + `CompactSlots` at `NotchLayout.hud`), for this target's #Previews and render tests.
// Not used by the app (the shell's NotchUI draws the real thing).
import CrannyCore
import SwiftUI

/// One HUD in the band of a display, over a backdrop so the black shape reads.
struct HUDBandPreview: View {
    let activity: HUDActivity
    var metrics: NotchMetrics = .reference
    var style: NoNotchStyle = .floatingIsland
    var theme = CrannyTheme()

    var body: some View {
        let layout = NotchLayout(metrics: metrics, noNotchStyle: style)
        let geometry = layout.hud
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
            NotchSurface(geometry: geometry, band: layout.band, openness: 0) {
                CompactSlots(layout: layout, slot: activity.slot,
                             leading: { activity.compactLeading() },
                             center: { EmptyView() },
                             trailing: { activity.compactTrailing() })
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: (geometry.outerWidth + 2 * Space.huge).rounded(), height: (geometry.bottom + Space.l).rounded())
        .environment(\.colorScheme, .dark)
        .crannyThemeRoot(theme)
    }
}

/// A sample activity on preview settings.
@MainActor func previewHUD(_ display: HUDDisplay, configure: (SettingsStore) -> Void = { _ in }) -> HUDActivity {
    let settings = CrannyServices.preview().settings
    configure(settings)
    return HUDActivity.sample(settings: settings, display: display)
}

#Preview("Band preview · brightness") {
    HUDBandPreview(activity: previewHUD(HUDDisplay(kind: .brightness, level: 0.75)))
}
