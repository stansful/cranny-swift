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

/// Fixed sizes of the Tray's pieces (DESIGN.md §8.1). Everything else comes from the theme.
enum TrayMetrics {
    /// Tile: 64 × 66 (44-pt thumbnail + caption).
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
