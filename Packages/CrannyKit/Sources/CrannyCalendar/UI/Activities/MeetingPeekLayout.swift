// CrannyCalendar/UI/Activities/MeetingPeekLayout.swift — the 52-pt peek row anatomy shared by both meeting
// activities (DESIGN.md §9.3): [visual 40 × 40] 12 [title `headline` / detail `callout`] 8 [≤ 3 controls].
// CrannyNotchUI adds the 12-pt outer insets.
import CrannyCore
import SwiftUI

struct MeetingPeekLayout<Visual: View, Title: View, Detail: View, Controls: View>: View {
    @Environment(\.cranny) private var theme
    private let visual: Visual, title: Title, detail: Detail, controls: Controls

    init(@ViewBuilder visual: () -> Visual, @ViewBuilder title: () -> Title,
         @ViewBuilder detail: () -> Detail, @ViewBuilder controls: () -> Controls) {
        self.visual = visual(); self.title = title(); self.detail = detail(); self.controls = controls()
    }

    var body: some View {
        HStack(spacing: Space.l) {
            visual.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: Space.xxs) {
                title
                    .crannyFont(.headline)
                    .foregroundStyle(theme.palette.label)
                    .lineLimit(1)
                detail
                    .crannyFont(.callout)
                    .foregroundStyle(theme.palette.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.xs) { controls }
                .padding(.leading, Space.m - Space.l)                 // 8 pt before the controls (spacing is 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Peek layout") {
    MeetingPeekLayout {
        RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(.blue.opacity(0.3))
    } title: {
        Text(verbatim: "Design review")
    } detail: {
        Text(verbatim: "10:30–11:00 · Room 4")
    } controls: {
        Button {} label: { Image(systemName: "xmark") }.buttonStyle(CrannyIconButtonStyle(.plain))
    }
    .frame(width: 401, height: 52)
    .padding(.horizontal, Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
