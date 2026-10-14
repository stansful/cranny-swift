// CrannyQuickApps/UI/TileChrome.swift — what every launcher tile shares (DESIGN.md §7.3): the 56-pt cell with
// its face centred, the Dock-style running dot, the optional name, the hover well (`control`, r 12), the press
// scale and the edit-mode remove badge.
import CrannyCore
import SwiftUI

/// Face + running dot + optional name, laid out in one cell. Without a name the face is centred in the cell.
struct TileContent<Face: View>: View {
    @Environment(\.cranny) private var theme
    let metrics: TileMetrics
    let label: String?
    let isRunning: Bool
    let face: Face

    init(metrics: TileMetrics, label: String?, isRunning: Bool, @ViewBuilder face: () -> Face) {
        self.metrics = metrics; self.label = label; self.isRunning = isRunning; self.face = face()
    }

    var body: some View {
        let p = theme.palette
        let dotGap: CGFloat = 3
        VStack(spacing: 0) {
            face.frame(width: metrics.icon, height: metrics.icon)
            Circle()
                .fill(isRunning ? p.secondaryLabel : Color.clear)
                .frame(width: metrics.dot, height: metrics.dot)
                .padding(.top, dotGap)
                .animation(theme.animation(.hover), value: isRunning)
            if let label {
                Text(verbatim: label)
                    .crannyFont(.caption)
                    .foregroundStyle(p.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: metrics.tile - Space.xs)
                    .padding(.top, 1)
            }
        }
        // Without a name, shift down by half the dot row so the icon sits in the cell's centre.
        .offset(y: label == nil ? (dotGap + metrics.dot) / 2 : 0)
        .frame(width: metrics.tile, height: metrics.tile)
    }
}

/// The tile as a button: hover well, pressed well and a 0.94 press scale (no scale under Reduce Motion).
struct TileButtonStyle: ButtonStyle {
    let metrics: TileMetrics
    func makeBody(configuration: Configuration) -> some View { TileButtonBody(configuration: configuration, metrics: metrics) }
}

private struct TileButtonBody: View {
    @Environment(\.cranny) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    let configuration: ButtonStyleConfiguration
    let metrics: TileMetrics

    var body: some View {
        let p = theme.palette
        let well = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        configuration.label
            .scaleEffect(configuration.isPressed && !theme.reduceMotion ? 0.94 : 1)
            .frame(width: metrics.tile, height: metrics.tile)
            .background(well.fill(configuration.isPressed ? p.controlPressed : (hovered && isEnabled ? p.control : Color.clear)))
            .contentShape(well)
            .onHover { hovered = $0 }
            .animation(theme.animation(.hover), value: hovered)
            .animation(theme.animation(.press), value: configuration.isPressed)
    }
}

/// Edit mode: the "remove" badge on a tile's top-leading corner. 28-pt hit target around an 18-pt disc.
struct RemoveBadge: View {
    @Environment(\.cranny) private var theme
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let p = theme.palette
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: (size * 0.45).rounded(), weight: .bold))
                .foregroundStyle(p.label)
                .frame(width: size, height: size)
                .background(Circle().fill(p.controlPressed))
                .background(Circle().fill(p.surface))
                .overlay(Circle().strokeBorder(p.stroke, lineWidth: 1))
                .frame(width: HitTarget.preferred, height: HitTarget.preferred)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action"))
        .help(String(localized: "Remove from Quick Apps", bundle: .module, comment: "Quick Apps: edit-mode remove badge / tile action"))
    }
}

#Preview("Tile chrome") {
    let metrics = TileMetrics(tile: 56, showsLabels: false)
    let labelled = TileMetrics(tile: 56, showsLabels: true)
    let entry = ShortcutEntry(id: "A", name: "Rename screenshots", tint: .indigo)
    HStack(spacing: Space.m) {
        Button {} label: {
            TileContent(metrics: metrics, label: nil, isRunning: true) { ShortcutGlyph(entry: entry, size: metrics.icon) }
        }
        .buttonStyle(TileButtonStyle(metrics: metrics))
        Button {} label: {
            TileContent(metrics: labelled, label: "Rename", isRunning: false) { ShortcutGlyph(entry: entry, size: labelled.icon) }
        }
        .buttonStyle(TileButtonStyle(metrics: labelled))
        ZStack(alignment: .topLeading) {
            TileContent(metrics: metrics, label: nil, isRunning: false) { ShortcutGlyph(entry: entry, size: metrics.icon) }
            RemoveBadge(size: metrics.removeBadge) {}.offset(x: -2, y: -2)
        }
    }
    .padding(Space.l)
    .crannyCard(cells: 3)
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
