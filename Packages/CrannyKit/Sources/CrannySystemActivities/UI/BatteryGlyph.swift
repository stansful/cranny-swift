// CrannySystemActivities/UI/BatteryGlyph.swift — the code-drawn battery of the Charging and Low battery
// activities (DESIGN.md §9.2: "Code-drawn battery 24 × 12 (exact fill)"). Unlike the stepped SF Symbols it
// shows the exact level. While charging, a bolt sits in the middle with a cut-out gap around it.
import CrannyCore
import SwiftUI

struct BatteryGlyph: View {
    @Environment(\.cranny) private var theme
    /// 0…100.
    var percent: Int
    var fill: Color
    var showsBolt = false
    var size = CGSize(width: 24, height: 12)

    var body: some View {
        let p = theme.palette
        let nub = CGSize(width: max(1.5, (size.width * 0.07).rounded(.up)), height: (size.height * 0.4).rounded())
        let bodyWidth = size.width - nub.width - 1
        let radius = size.height * 0.3
        let inset: CGFloat = 2
        let inner = max(bodyWidth - inset * 2, 0)
        let level = CGFloat(min(max(percent, 0), 100)) / 100
        let fillWidth = level > 0 ? max(inner * level, 1) : 0
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(p.tertiaryLabel, lineWidth: 1)
                RoundedRectangle(cornerRadius: max(radius - inset, 1), style: .continuous)
                    .fill(fill)
                    .frame(width: fillWidth)
                    .padding(inset)
            }
            .frame(width: bodyWidth, height: size.height)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: nub.width, topTrailingRadius: nub.width, style: .continuous)
                .fill(p.tertiaryLabel)
                .frame(width: nub.width, height: nub.height)
        }
        .overlay {
            if showsBolt {
                ZStack {
                    bolt(height: size.height * 1.25).blendMode(.destinationOut)   // the gap around the bolt
                    bolt(height: size.height * 0.95).foregroundStyle(p.label)
                }
                .offset(x: -(nub.width + 1) / 2)
            }
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
        .animation(theme.animation(.contentSwap), value: percent)
        .accessibilityHidden(true)
    }

    private func bolt(height: CGFloat) -> some View {
        Image(systemName: "bolt.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}

#Preview("Battery glyph") {
    let theme = CrannyTheme()
    HStack(spacing: 16) {
        BatteryGlyph(percent: 82, fill: theme.palette.success, showsBolt: true)
        BatteryGlyph(percent: 100, fill: theme.palette.label)
        BatteryGlyph(percent: 20, fill: theme.palette.warning)
        BatteryGlyph(percent: 6, fill: theme.palette.danger)
        BatteryGlyph(percent: 54, fill: theme.palette.label, size: CGSize(width: 23, height: 12))
    }
    .padding(24)
    .background(.black)
    .crannyThemeRoot(theme)
}
