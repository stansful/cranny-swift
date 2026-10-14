// CrannyEffects/RippleModifier.swift — Song change (DESIGN.md §4.3, §5.5, §5.6 `songRipple`): when the track changes,
// the ambient light inside the modified view gets a 0.6-s radial ripple from the camera (a distortion on the shader
// paths) plus an energy pulse on every path. Reduce Motion: no ripple (the palette cross-fade carries the change).
import CrannyCore
import Foundation
import SwiftUI

public extension View {
    /// Plays the song-change ripple on the ambient light inside this view whenever `trigger` changes (for example
    /// the track identifier, or the scene's `delightSerial` while `delight == .songRipple`). Content other than the
    /// ambient light is never distorted.
    func songChangeRipple(_ trigger: some Equatable) -> some View {
        modifier(SongChangeRipple(trigger: trigger))
    }
}

struct SongChangeRipple<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.cranny) private var theme
    @State private var start: Date?

    func body(content: Content) -> some View {
        content
            .environment(\.ambientRippleStart, start)
            .onChange(of: trigger) { _, _ in
                start = theme.reduceMotion || theme.motion == .instant ? nil : Date()
            }
    }
}

// MARK: - Previews

private struct RipplePreview: View {
    @State private var track = 0
    var body: some View {
        AmbientLayer(palette: .afterglow, level: .vivid, effect: .aurora, energy: 0, budget: .previewRunning)
            .songChangeRipple(track)
            .frame(width: 656, height: 170)
            .background(.black)
            .onTapGesture { track += 1 }
    }
}

#Preview("Song change ripple (click to change track)") {
    RipplePreview()
        .crannyThemeRoot(CrannyTheme())
}
