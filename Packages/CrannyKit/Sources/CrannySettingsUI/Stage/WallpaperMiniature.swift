// CrannySettingsUI/Stage/WallpaperMiniature.swift — the backdrop of the preview stage (DESIGN.md §11.2): the top of
// the user's own wallpaper (when it is safe to read, see `WallpaperSource`), otherwise a neutral dark gradient.
// Decorative, so hidden from VoiceOver.
import AppKit
import CrannyCore
import SwiftUI

struct WallpaperMiniature: View {
    let miniature: WallpaperSource.Miniature?

    var body: some View {
        ZStack {
            NeutralStageGradient()
            if let miniature {
                Image(decorative: miniature.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The neutral backdrop: Cranny's night and graphite with a faint brand glow, so the black notch still reads.
struct NeutralStageGradient: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [BrandColor.graphite.color, BrandColor.night.color], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [BrandColor.iris.color(0.28), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [BrandColor.lagoon.color(0.20), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 380)
        }
    }
}

#Preview("Neutral stage") {
    WallpaperMiniature(miniature: nil).frame(width: 640, height: 176)
}
