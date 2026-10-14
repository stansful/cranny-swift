// CrannyTimer/UI/TimerPresets.swift — the preset chips of the Timer widget (DESIGN.md §7.7): a 2 × 2 grid of round
// tiles on an idle 2-cell card ("1 · 5 · 10 · 25 min"), a column of capsule chips beside the ring at 3 cells.
// One click starts that duration.
import CrannyCore
import Foundation
import SwiftUI

/// 2 cells, idle: four tiles, each a big number over a small unit ("25" / "MIN").
struct TimerPresetGrid: View {
    let presets: [Int]
    let side: CGFloat
    let start: @MainActor (Int) -> Void

    var body: some View {
        let tile = max((side - Space.m) / 2, HitTarget.preferred)
        let rows = stride(from: 0, to: presets.count, by: 2).map { Array(presets[$0..<min($0 + 2, presets.count)]) }
        Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, seconds in
                        Button { start(seconds) } label: { TimerPresetTileLabel(seconds: seconds) }
                            .buttonStyle(TimerTileButtonStyle())
                            .frame(width: tile, height: tile)
                            .help(TimerCopy.startTitle(seconds: seconds))
                            .accessibilityLabel(Text(TimerCopy.startTitle(seconds: seconds)))
                    }
                }
            }
        }
        .frame(width: side, height: side)
    }
}

private struct TimerPresetTileLabel: View {
    @Environment(\.cranny) private var theme
    let seconds: Int
    var body: some View {
        let face = TimerFormat.presetFace(seconds)
        VStack(spacing: 0) {
            Text(verbatim: face.value)
                .crannyFont(.numeral)
                .minimumScaleFactor(0.6)
                .foregroundStyle(theme.palette.label)
            if face.unit != .clock {
                Text(TimerCopy.unit(face.unit))
                    .crannyFont(.micro)
                    .foregroundStyle(theme.palette.secondaryLabel)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Space.xxs)
    }
}

/// 3 cells: a column of chips beside the ring ("1 min", "5 min" …), each with a ≥ 24-pt tall hit area.
struct TimerPresetColumn: View {
    let presets: [Int]
    let width: CGFloat
    let height: CGFloat
    let start: @MainActor (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, seconds in
                Button { start(seconds) } label: {
                    Text(TimerFormat.short(seconds)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }
                .buttonStyle(CrannyChipButtonStyle())
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .help(TimerCopy.startTitle(seconds: seconds))
                .accessibilityLabel(Text(TimerCopy.startTitle(seconds: seconds)))
            }
        }
        .frame(width: width, height: height)
    }
}

/// A preset tile: `control` fill in the user's button shape (capsule → a circle), hover and press like
/// `CrannyIconButtonStyle`.
struct TimerTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TileBody(configuration: configuration) }

    private struct TileBody: View {
        @Environment(\.cranny) private var theme
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration

        var body: some View {
            let p = theme.palette
            let shape = CrannyButtonShape(theme.buttonShape)
            configuration.label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(configuration.isPressed ? p.controlPressed : hovered ? p.controlHover : p.control))
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
                .animation(theme.animation(.press), value: configuration.isPressed)
        }
    }
}

#Preview("Presets · grid and column") {
    HStack(alignment: .top, spacing: Space.l) {
        TimerPresetGrid(presets: [60, 300, 600, 1500], side: 96) { _ in }
            .crannyCard(cells: 2)
        TimerPresetColumn(presets: [60, 300, 600, 1500], width: 64, height: 96) { _ in }
            .padding(Space.l)
            .background(.black)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
