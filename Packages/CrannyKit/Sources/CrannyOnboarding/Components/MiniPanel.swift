// CrannyOnboarding/Components/MiniPanel.swift — a starting layout drawn as a miniature open panel (DESIGN.md
// §12.1 step 4): the real open geometry of the reference notch (NotchShape, ears included) and one smoked card
// per widget at its true width in cells, all scaled by one factor, so the four presets compare at a glance
// (Minimal is visibly narrower). The miniature is a notch surface, hence always dark with its own theme root.
import CrannyCore
import SwiftUI

struct MiniPanel: View {
    let items: [NookItem]
    let symbols: [WidgetID: String]
    /// Points per reference point (the widest preset, 10 cells, fills `width`).
    let scale: CGFloat

    static func scale(forWidth width: CGFloat) -> CGFloat {
        width / NotchLayout(metrics: .reference).open(columns: 10).outerWidth
    }

    var body: some View {
        MiniPanelBody(items: items, symbols: symbols)
            .scaleEffect(scale, anchor: .top)
            .frame(width: Self.layout.open(columns: 10).outerWidth * scale,
                   height: Self.geometry(items).bottom * scale, alignment: .top)
            .crannyThemeRoot(CrannyTheme())
            .accessibilityHidden(true)                       // the card's label lists the widgets
    }

    fileprivate static let layout = NotchLayout(metrics: .reference)

    fileprivate static func geometry(_ items: [NookItem]) -> NotchGeometry {
        layout.open(columns: items.reduce(0) { $0 + $1.cells })
    }
}

/// Reference-size drawing (scaled by the parent).
private struct MiniPanelBody: View {
    @Environment(\.cranny) private var theme
    let items: [NookItem]
    let symbols: [WidgetID: String]

    var body: some View {
        let layout = MiniPanel.layout
        let geometry = MiniPanel.geometry(items)
        let grid = layout.grid
        ZStack(alignment: .top) {
            NotchShape(geometry).fill(theme.palette.surface)
            HStack(spacing: grid.gutter) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let shape = RoundedRectangle(cornerRadius: grid.cardRadius, style: .continuous)
                    shape.fill(theme.palette.card)
                        .overlay(shape.strokeBorder(theme.palette.hairline, lineWidth: StrokeWidth.regular))
                        .overlay {
                            Image(systemName: symbols[item.widget] ?? "app.dashed")
                                .font(.system(size: grid.cell * 0.72, weight: .medium))
                                .foregroundStyle(theme.palette.secondaryLabel)
                        }
                        .frame(width: grid.width(cells: item.cells), height: grid.height)
                }
            }
            .padding(.top, layout.headerHeight + grid.headerGap)
        }
        .frame(width: layout.open(columns: 10).outerWidth, height: geometry.bottom, alignment: .top)
    }
}

#Preview("Mini panels") {
    VStack(spacing: Space.l) {
        ForEach(NookPreset.allCases, id: \.self) { preset in
            MiniPanel(items: preset.items, symbols: [.media: "music.note", .calendar: "calendar", .quickApps: "app.dashed",
                                                     .notes: "note.text", .todos: "checklist", .timer: "timer",
                                                     .mirror: "web.camera"],
                      scale: MiniPanel.scale(forWidth: 120))
        }
    }
    .padding(Space.xxl)
}
