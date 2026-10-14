// CrannyCalendar/UI/EventStyle.swift — the calendar colour as a foreground mark, lifted until it reads on the
// surface it sits on (DESIGN.md §2.1: every mark derived from content is guarded; ≥ 4.5:1, 7:1 under Increase
// Contrast), and the small capsule that carries it.
import CrannyCore
import SwiftUI

extension CrannyTheme {
    /// An event's colour on a card (the widget).
    func eventColor(_ rgb: RGB) -> Color {
        rgb.legible(on: palette.spec.cardOverBlack, ratio: accentContrast).color
    }
    /// An event's colour on the black band and peek.
    func bandEventColor(_ rgb: RGB) -> Color {
        rgb.legible(on: .black, ratio: accentContrast).color
    }
}

/// The 3-pt calendar-colour capsule in front of a row (DESIGN.md §7.2: 3 × 14; two lines tall when featured).
struct CalendarMark: View {
    @Environment(\.cranny) private var theme
    let color: RGB
    var height: CGFloat = 14
    var dimmed = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(theme.eventColor(color))
            .frame(width: 3, height: height)
            .opacity(dimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

#Preview("Calendar marks") {
    HStack(spacing: Space.m) {
        ForEach([0x1BADF8, 0xCC73E1, 0x63DA38, 0x2C3E8F, 0x7A1010], id: \.self) { hex in
            CalendarMark(color: RGB(hex: UInt32(hex)))
            CalendarMark(color: RGB(hex: UInt32(hex)), height: 28)
            CalendarMark(color: RGB(hex: UInt32(hex)), dimmed: true)
        }
    }
    .padding()
    .crannyCard(cells: 3)
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
