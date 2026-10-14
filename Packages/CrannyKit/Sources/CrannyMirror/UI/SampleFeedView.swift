// CrannyMirror/UI/SampleFeedView.swift — a drawn stand-in for camera frames: a head-and-shoulders silhouette in a
// dim room, lit by a window on one side, in the brand ramp. Used ONLY by #Previews and the Debug visual-QA
// scenarios (`--qa-mirror`), never by the live module: there is no "fake camera" a user could see.
import CrannyCore
import SwiftUI

struct SampleFeedView: View {
    /// Flips the scene like the real feed, so the flip button visibly works in QA.
    var isMirrored = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let head = h * 0.3
            ZStack {
                LinearGradient(colors: [BrandColor.graphite.color, BrandColor.night.color], startPoint: .top, endPoint: .bottom)
                // A window on the left: cool daylight falling across the room (asymmetric: flipping is visible).
                RadialGradient(colors: [BrandColor.sky.color(0.42), BrandColor.sky.color(0)],
                               center: UnitPoint(x: 0, y: 0.15), startRadius: 0, endRadius: max(w, h) * 0.85)
                // A warm lamp out of frame on the right.
                RadialGradient(colors: [BrandColor.ember.color(0.18), BrandColor.ember.color(0)],
                               center: UnitPoint(x: 1.1, y: 0.8), startRadius: 0, endRadius: max(w, h) * 0.6)
                Silhouette(head: head)
                    .position(x: w * 0.5, y: h * 0.6)
            }
            .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Head and shoulders, darker than the room, with a soft rim of window light on the left edge.
private struct Silhouette: View {
    let head: CGFloat

    var body: some View {
        ZStack {
            figure.fill(LinearGradient(colors: [BrandColor.graphite.color, BrandColor.night.color],
                                       startPoint: .top, endPoint: .bottom))
            figure.stroke(BrandColor.mint.color(0.7), lineWidth: 2)
                .blur(radius: 1.5)
                .mask(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .center))
        }
        .frame(width: head * 2.7, height: head * 3)
    }

    private var figure: some Shape { SilhouetteShape() }
}

private nonisolated struct SilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let headWidth = rect.width * 0.33, headHeight = rect.height * 0.37
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.midX - headWidth / 2, y: rect.minY, width: headWidth, height: headHeight))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + headHeight * 0.9, width: rect.width,
                                       height: rect.height), cornerSize: CGSize(width: rect.width * 0.36, height: rect.height * 0.36),
                            style: .continuous)
        return path
    }
}

#Preview("Sample feed · 2 and 3 cells") {
    HStack(spacing: Space.m) {
        SampleFeedView().crannyCard(cells: 2, frameless: true)
        SampleFeedView(isMirrored: false).crannyCard(cells: 3, frameless: true)
    }
    .padding(Space.l)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
