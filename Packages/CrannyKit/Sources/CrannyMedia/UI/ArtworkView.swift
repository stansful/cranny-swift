// CrannyMedia/UI/ArtworkView.swift — album artwork at any size (compact 20u r 5u, satellite, peek 40 r 10,
// widget 72/96 r inner) with the optional album glow (DESIGN.md §5.1: accent 30 %, r 36, scale 1.08 — the
// radius scales with the artwork) and the missing-artwork tile (accent gradient + `music.note`, §7.1).
// Artwork swaps with `.blurReplace` + `contentSwap`.
import CoreGraphics
import CrannyCore
import SwiftUI

struct ArtworkView: View {
    @Environment(\.cranny) private var theme
    let image: CGImage?
    /// Identity of the artwork (track key): a change cross-fades with `.blurReplace`.
    let identity: String?
    let size: CGFloat
    let radius: CGFloat
    /// Album glow behind the artwork (Appearance ▸ Album glow).
    var glows = false
    /// The album accent for the glow and the missing-artwork tile (nil = theme accent).
    var accent: RGB?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint = accent ?? theme.accent
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(theme.reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                    .id(identity)
            } else {
                MissingArtwork(tint: tint, size: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(theme.palette.hairline, lineWidth: 0.5) }
        .background {
            if glows && !theme.reduceTransparency {
                shape.fill(tint.color)
                    .scaleEffect(1.08)
                    .blur(radius: Glow.albumHaloRadius * size / 96)
                    .opacity(Glow.albumHaloOpacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(theme.animation(.contentSwap), value: identity)
        .animation(theme.animation(.colorShift), value: tint)
        .accessibilityHidden(true)
    }
}

/// Accent gradient + note glyph, used until (or when there is no) artwork.
private struct MissingArtwork: View {
    @Environment(\.cranny) private var theme
    let tint: RGB
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.color(0.95), tint.color(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: max(size * 0.42, 9), weight: .semibold))
                .foregroundStyle(tint.onColor.color(0.85))
        }
    }
}

#Preview("Artwork sizes") {
    let sample = SampleMedia.artwork()
    HStack(spacing: Space.xl) {
        ArtworkView(image: sample?.image, identity: "a", size: 96, radius: Radius.inner, glows: true, accent: sample?.palette.accent)
        ArtworkView(image: sample?.image, identity: "a", size: 40, radius: Radius.artPeek, glows: true, accent: sample?.palette.accent)
        ArtworkView(image: sample?.image, identity: "a", size: 20, radius: Radius.artCompact)
        ArtworkView(image: nil, identity: nil, size: 96, radius: Radius.inner)
        ArtworkView(image: nil, identity: nil, size: 20, radius: Radius.artCompact)
    }
    .padding(Space.huge)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
