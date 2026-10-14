// CrannySettingsUI/Stage/StageSampleView.swift — the drawing of the stage's stand-in activities, per placement
// (DESIGN.md §9.1–§9.3, §10): one datum per side in compact, a 52-pt row in peek, a glyph in the satellite.
// Tokens only (`@Environment(\.cranny)`, `crannyFont`, `Space`, `Radius`); a still frame, no clocks.
import CrannyCore
import Foundation
import SwiftUI

struct StageSampleView: View {
    @Environment(\.cranny) private var theme
    let sample: StageSampleActivity.Sample
    let placement: ActivityPlacement

    var body: some View {
        switch placement {
        case .compactLeading: leading
        case .compactTrailing: trailing
        case .minimal: minimal
        case .peekRow: peekRow
        }
    }

    private var u: CGFloat { theme.notchUnit }

    @ViewBuilder private var leading: some View {
        switch sample {
        case .nowPlaying: SampleArtwork(size: 20 * u, radius: Radius.artCompact * u)
        case .timer: SampleRing(diameter: 16 * u, lineWidth: StrokeWidth.ringCompact)
        case .meeting:
            HStack(spacing: Space.xs * u) {
                Circle().fill(theme.palette.info).frame(width: 7 * u, height: 7 * u)
                Text(verbatim: StageSampleText.meetingCountdown).crannyFont(.compactLabel).foregroundStyle(theme.palette.label)
            }
        case .volume:
            Image(systemName: "speaker.wave.3.fill", variableValue: StageSampleText.volume)
                .font(.system(size: 13 * u, weight: .semibold))
                .foregroundStyle(theme.palette.label)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch sample {
        case .nowPlaying: SampleVisualizer()
        case .timer: Text(verbatim: StageSampleText.timerValue).crannyFont(.compact).foregroundStyle(theme.palette.label)
        case .meeting: SampleJoinCapsule(scale: u)
        case .volume: LevelBar(value: StageSampleText.volume).frame(width: 64 * u)
        }
    }

    @ViewBuilder private var minimal: some View {
        switch sample {
        case .nowPlaying: SampleArtwork(size: 16 * u, radius: 8 * u)
        case .timer: SampleRing(diameter: 14 * u, lineWidth: StrokeWidth.ringCompact)
        case .meeting: Circle().fill(theme.palette.info).frame(width: 7 * u, height: 7 * u)
        case .volume: Image(systemName: "speaker.wave.3.fill").font(.system(size: 11 * u, weight: .semibold))
        }
    }

    /// `[12] [visual 40, r 10] [12] [title / subtitle] [8] [≤ 3 controls] [12]` (DESIGN.md §9.3).
    private var peekRow: some View {
        HStack(spacing: Space.l) {
            peekVisual.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: peekTitle).crannyFont(.headline).foregroundStyle(theme.palette.label).lineLimit(1)
                Text(verbatim: peekSubtitle).crannyFont(.callout).foregroundStyle(theme.palette.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: Space.m)
            peekControls
        }
    }

    @ViewBuilder private var peekVisual: some View {
        switch sample {
        case .nowPlaying: SampleArtwork(size: 40, radius: Radius.artPeek)
        case .timer: SampleRing(diameter: 34, lineWidth: StrokeWidth.ring)
        case .meeting:
            RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).fill(theme.palette.control)
                .overlay(Image(systemName: "calendar").font(.system(size: 17, weight: .medium)).foregroundStyle(theme.palette.info))
        case .volume: Image(systemName: "speaker.wave.3.fill").font(.system(size: 17, weight: .medium))
        }
    }

    private var peekTitle: String {
        switch sample {
        case .nowPlaying: StageSampleText.songTitle
        case .timer: StageSampleText.timerLabel
        case .meeting: StageSampleText.meetingTitle
        case .volume: StageSampleText.volumeValue
        }
    }

    private var peekSubtitle: String {
        switch sample {
        case .nowPlaying: StageSampleText.artist
        case .timer: String(localized: "\(StageSampleText.timerValue) left", bundle: .module,
                            comment: "Settings preview stage: time left on the sample timer (peek row)")
        case .meeting: StageSampleText.meetingDetail
        case .volume: ""
        }
    }

    @ViewBuilder private var peekControls: some View {
        switch sample {
        case .nowPlaying:
            HStack(spacing: Space.xs) {
                ForEach(["backward.fill", "pause.fill", "forward.fill"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                        .frame(width: HitTarget.preferred, height: HitTarget.preferred)
                }
            }
            .foregroundStyle(theme.palette.label)
        case .timer:
            HStack(spacing: Space.xs) {
                ForEach(["pause.fill", "stop.fill"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .frame(width: HitTarget.preferred, height: HitTarget.preferred)
                        .background(Circle().fill(theme.palette.control))
                }
            }
            .foregroundStyle(theme.palette.label)
        case .meeting: SampleJoinCapsule(scale: 1.2)
        case .volume: EmptyView()
        }
    }
}

/// A sample "album cover": a brand gradient with a note, never a real artwork.
private struct SampleArtwork: View {
    let size: CGFloat
    let radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [BrandColor.iris.color, BrandColor.rose.color, BrandColor.ember.color],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
            .frame(width: size, height: size)
    }
}

/// The timer ring in `warning` orange (DESIGN.md decision 19).
private struct SampleRing: View {
    @Environment(\.cranny) private var theme
    let diameter: CGFloat
    let lineWidth: CGFloat
    var body: some View {
        ProgressRing(progress: StageSampleText.timerProgress, color: theme.palette.warning, lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
    }
}

/// Five static accent bars: 3-pt bars, 2-pt gaps, 4–16 pt tall (DESIGN.md §9.2), a still frame.
private struct SampleVisualizer: View {
    @Environment(\.cranny) private var theme
    var body: some View {
        let u = theme.notchUnit
        HStack(alignment: .center, spacing: 2 * u) {
            ForEach(Array([7.0, 13, 16, 10, 5].enumerated()), id: \.offset) { _, height in
                Capsule(style: .continuous).fill(theme.accentColor).frame(width: 3 * u, height: CGFloat(height) * u)
            }
        }
    }
}

/// Join: a `success` capsule with a black `person.2.wave.2.fill` (DESIGN.md §9.2, decision 15).
private struct SampleJoinCapsule: View {
    @Environment(\.cranny) private var theme
    let scale: CGFloat
    var body: some View {
        Image(systemName: "person.2.wave.2.fill")
            .font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: 34 * scale, height: 20 * scale)
            .background(Capsule(style: .continuous).fill(theme.palette.success))
    }
}

#Preview("Stage samples · compact") {
    VStack(spacing: 12) {
        ForEach(StageSampleActivity.Sample.allCases, id: \.self) { sample in
            HStack(spacing: 40) {
                StageSampleView(sample: sample, placement: .compactLeading)
                StageSampleView(sample: sample, placement: .compactTrailing)
            }
        }
    }
    .padding(20)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("Stage samples · peek rows") {
    VStack(spacing: 0) {
        ForEach(StageSampleActivity.Sample.allCases, id: \.self) { sample in
            StageSampleView(sample: sample, placement: .peekRow).frame(height: 52).padding(.horizontal, 12)
        }
    }
    .frame(width: 425)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
