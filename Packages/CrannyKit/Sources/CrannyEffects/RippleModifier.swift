// CrannyEffects/RippleModifier.swift — Song change (DESIGN.md §4.3, §5.5, §5.6 `songRipple`): when the track changes,
// the ambient light inside the modified view gets a 0.6-s radial ripple from the camera (a distortion on the shader
// paths) plus an energy pulse on every path. Calm, Instant and Reduce Motion: no ripple and no pulse (DESIGN.md §5.5:
// "Colour only"; the palette cross-fade carries the change).
import CrannyCore
import Foundation
import SwiftUI

public extension View {
    /// Plays the song-change ripple on the ambient light inside this view whenever `trigger` changes. Content other
    /// than the ambient light is never distorted. Nothing plays under Calm, Instant or Reduce Motion.
    ///
    /// Pass the scene's `delightSerial` while `delight == .songRipple`: the shell has already applied the delight
    /// caps (one moment at a time, none in full screen, none while Live Activities are paused, DESIGN.md §5.5). A raw
    /// trigger such as the track identifier bypasses those caps, so a caller using one must apply them itself.
    func songChangeRipple(_ trigger: some Equatable) -> some View {
        modifier(SongChangeRipple(trigger: trigger))
    }
}

struct SongChangeRipple<Trigger: Equatable>: ViewModifier {
    /// Whether the ripple plays: not under Calm, Instant or Reduce Motion (DESIGN.md §5.5, "Colour only").
    nonisolated static func plays(reduceMotion: Bool, motion: MotionPersonality) -> Bool {
        !reduceMotion && motion != .calm && motion != .instant
    }

    let trigger: Trigger
    @Environment(\.cranny) private var theme
    @State private var start: Date?

    func body(content: Content) -> some View {
        content
            .environment(\.ambientRippleStart, start)
            .onChange(of: trigger) { _, _ in
                start = Self.plays(reduceMotion: theme.reduceMotion, motion: theme.motion) ? Date() : nil
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
