// CrannyTray/UI/TrayThumbnailView.swift — a tile's picture (DESIGN.md §8.1: 44-pt Quick Look thumbnail, r 8).
// Real previews (photos, PDFs, videos) fill the rounded square; type icons are shown whole. While the thumbnail is
// generated off-main, the type icon stands in, so nothing pops from empty.
import AppKit
import CrannyCore
import SwiftUI
import UniformTypeIdentifiers

struct TrayThumbnailView: View {
    @Environment(\.cranny) private var theme
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    let type: UTType
    let cache: ThumbnailCache?
    var side: CGFloat = TrayMetrics.thumbnail
    @State private var thumbnail: TrayThumbnail?

    var body: some View {
        let radius = theme.grid.innerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let thumbnail, !thumbnail.isIcon {
                Image(decorative: thumbnail.image, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(theme.palette.hairline, lineWidth: StrokeWidth.hairline(displayScale)))
            } else if let thumbnail {
                Image(decorative: thumbnail.image, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: type))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: side, height: side)
        .task(id: url) {
            guard let url, let cache else { return }
            thumbnail = await cache.thumbnail(for: url, pointSize: side, scale: displayScale)
        }
        .accessibilityHidden(true)
    }
}

/// Fixed sizes of the Tray's pieces (DESIGN.md §8.1). Everything else comes from the theme; the captioned tile grows
/// with Cranny's Text size (`TrayTileLayout`).
nonisolated enum TrayMetrics {
    /// Tile at Standard text size: 64 × 66 (44-pt thumbnail + caption).
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 66
    static let thumbnail: CGFloat = 44
    /// Chips row (22-pt capsules).
    static let chipHeight: CGFloat = 22
    /// The hover ✕ (16-pt circle) and the selection check badge (14 pt).
    static let removeBadge: CGFloat = 16
    static let checkBadge: CGFloat = 14
    /// The running ring and the "new" dot.
    static let progressRing: CGFloat = 22
    static let newDot: CGFloat = 6
    /// Horizontal fade at the ends of scrolling rows.
    static let fade: CGFloat = 12
}

/// A captioned tile's size at a Text size (DESIGN.md §8.1 64 × 66 at Standard; §16: larger text grows the tile, so the
/// caption never reaches the 1.5-pt selection ring). Inside the well: `Space.xs`, the 44-pt thumbnail, one caption line
/// (its own line height, which holds the space above the letters), `Space.xs`.
nonisolated struct TrayTileLayout: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    /// The caption's line box (11-pt `caption` at Standard: 14 pt).
    let captionHeight: CGFloat
    /// Gap between the tile row and the chip row of the Tray page.
    let rowSpacing: CGFloat

    init(textSize: CrannyTextSize, grid: NookGrid) {
        let style = CrannyTextStyle.caption
        let points = style.pointSize(textSize: textSize, notchUnit: 1)
        captionHeight = (style.spec.lineHeight * points / style.spec.size).rounded(.up)
        height = Space.xs + TrayMetrics.thumbnail + captionHeight + Space.xs
        width = (TrayMetrics.tileWidth * max(textSize.scale, 1)).rounded()
        // The page card holds the tile row, this gap and the chip row; dense grids shrink the gap, never the tiles.
        let content = grid.height - 2 * grid.density.cardPadding
        rowSpacing = max(min(Space.m, content - height - Self.chipRowHeight(textSize: textSize)), 0)
    }

    init(theme: CrannyTheme) { self.init(textSize: theme.textSize, grid: theme.grid) }

    /// The chip row: 22-pt capsules, taller only if the chip text (caption semibold) outgrows them.
    static func chipRowHeight(textSize: CrannyTextSize) -> CGFloat {
        let style = CrannyTextStyle.caption
        let points = style.pointSize(textSize: textSize, notchUnit: 1)
        return max(TrayMetrics.chipHeight, (style.spec.lineHeight * points / style.spec.size).rounded(.up))
    }
}

#Preview("Thumbnails") {
    HStack(spacing: Space.m) {
        TrayThumbnailView(url: nil, type: .pdf, cache: nil)
        TrayThumbnailView(url: nil, type: .png, cache: nil)
        TrayThumbnailView(url: nil, type: .zip, cache: nil)
        TrayThumbnailView(url: nil, type: .folder, cache: nil)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
