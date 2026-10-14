// CrannySettingsUI/Stage/MenuBarMiniature.swift — an abstract menu bar across the top of the preview stage
// (DESIGN.md §11.2), as tall as the real one (the band) so the notch sits in it at 1:1: menu titles on the left,
// status items and a clock on the right, the camera housing's width kept clear on notched displays. Shapes only,
// no Apple logo or real menu text; decorative, so hidden from VoiceOver.
import CrannyCore
import SwiftUI

struct MenuBarMiniature: View {
    let layout: NotchLayout
    /// The wallpaper under the bar is light: draw dark content on a light bar.
    let isLight: Bool

    var body: some View {
        let ink = isLight ? Color.black : Color.white
        let titles: [CGFloat] = [30, 40, 36, 44]
        let items: [CGFloat] = [14, 14, 16]
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                Capsule().fill(ink.opacity(0.85)).frame(width: 12, height: 12)
                ForEach(Array(titles.enumerated()), id: \.offset) { index, width in
                    Capsule().fill(ink.opacity(index == 0 ? 0.8 : 0.55)).frame(width: width, height: 6)
                }
            }
            .padding(.leading, 16)
            Spacer(minLength: layout.metrics.hasNotch ? layout.middle() + 40 : 40)
            HStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, width in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(ink.opacity(0.6)).frame(width: width, height: 10)
                }
                Capsule().fill(ink.opacity(0.7)).frame(width: 50, height: 6)
            }
            .padding(.trailing, 16)
        }
        .frame(height: layout.band)
        .frame(maxWidth: .infinity)
        .clipped()
        .background((isLight ? Color.white : Color.black).opacity(isLight ? 0.35 : 0.25))
        .accessibilityHidden(true)
    }
}

#Preview("Menu bar · notch") {
    MenuBarMiniature(layout: NotchLayout(metrics: .reference), isLight: false)
        .frame(width: 640)
        .background(NeutralStageGradient())
}

#Preview("Menu bar · light, no notch") {
    MenuBarMiniature(layout: NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 30, screenWidth: 1920)),
                     isLight: true)
        .frame(width: 640)
        .background(Color.teal)
}
