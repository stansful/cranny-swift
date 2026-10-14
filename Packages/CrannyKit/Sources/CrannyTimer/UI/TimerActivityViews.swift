// CrannyTimer/UI/TimerActivityViews.swift — what the two timer activities draw in the band, the satellite and the
// peek row (DESIGN.md §9.1–§9.3). One datum per side; peek rows: [visual 40] [title/subtitle] [≤ 3 controls].
import CrannyCore
import Foundation
import SwiftUI

// MARK: - Band

/// Leading wing and satellite of the running timer: a 16u ring in `warning`. It flies to the widget's ring when the
/// panel opens (`MatchedID.timerRing`). It is on screen whenever the activity is (compact, peek, minimal, glyph form),
/// so it keeps the activity's VoiceOver value current.
struct TimerCompactRing: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    var body: some View {
        TimerRing(state: model.state, diameter: TimerMetrics.compactRing * theme.notchUnit, lineWidth: StrokeWidth.ringCompact)
            .notchMatched(MatchedID.timerRing)
            .refreshesSpokenTime(model)
    }
}

/// Trailing wing of the running timer: "4:59" (`compact`; `warning` in the last minute; dimmed while paused).
/// Nothing in the glyph form of Large / Extra Large text (no clock runs then either).
struct TimerCompactValue: View {
    let model: TimerModel
    var body: some View {
        if !model.bandUsesGlyphForm {
            TimerDigits(state: model.state, style: .compact, rolls: false, warnsInLastMinute: true)
                .minimumScaleFactor(0.75)
                .accessibilityHidden(true)
        }
    }
}

/// Leading wing of "Timer done": the `timer` glyph in `warning`, bouncing once as it arrives.
struct TimerDoneGlyph: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    /// The band scales with the notch unit; the peek row does not.
    var inPeek = false
    @State private var arrived = false

    var body: some View {
        let size = inPeek ? TimerMetrics.peekGlyph : TimerMetrics.compactGlyph * theme.notchUnit
        let glyph = Image(systemName: "timer")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(theme.palette.warning)
            .accessibilityHidden(true)
        Group {
            if theme.reduceMotion || theme.motion == .instant {
                glyph
            } else {
                glyph.symbolEffect(.bounce, options: .nonRepeating, value: model.doneRevision + (arrived ? 1 : 0))
            }
        }
        .onAppear { arrived = true }
    }
}

/// Trailing wing of "Timer done": "Done" (nothing in the glyph form).
struct TimerDoneLabel: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    var body: some View {
        if !model.bandUsesGlyphForm {
            Text(TimerCopy.done)
                .crannyFont(.compact)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(theme.palette.label)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Peek rows

/// Running: ring 40 · "4:59" / "Ends 14:35" · ⏸ ⏹ · +1 min.
struct TimerRunningPeekRow: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel

    var body: some View {
        let state = model.state
        HStack(spacing: Space.l) {
            TimerRing(state: state, diameter: TimerMetrics.peekVisual, lineWidth: StrokeWidth.ring)
                .frame(width: TimerMetrics.peekVisual, height: TimerMetrics.peekVisual)
            VStack(alignment: .leading, spacing: 0) {
                TimerDigits(state: state, style: .numeral)
                TimerEndLabel(state: state)
                    .crannyFont(.callout)
                    .foregroundStyle(theme.palette.secondaryLabel)
            }
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                TimerPauseButton(model: model, size: HitTarget.preferred)
                TimerStopButton(model: model, size: HitTarget.preferred)
                TimerAddMinuteChip(model: model)
            }
        }
    }
}

/// Done: full ring + glyph · "Timer done" / "5 min" · +1 min · Stop (prominent).
struct TimerDonePeekRow: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel

    var body: some View {
        HStack(spacing: Space.l) {
            ZStack {
                TimerRing(state: model.state, diameter: TimerMetrics.peekVisual, lineWidth: StrokeWidth.ring)
                TimerDoneGlyph(model: model, inPeek: true)
            }
            .frame(width: TimerMetrics.peekVisual, height: TimerMetrics.peekVisual)
            VStack(alignment: .leading, spacing: 0) {
                Text(TimerCopy.timerDone)
                    .crannyFont(.headline)
                    .foregroundStyle(theme.palette.label)
                Text(TimerFormat.short(Int(model.state.total)))
                    .crannyFont(.callout)
                    .foregroundStyle(theme.palette.secondaryLabel)
            }
            .lineLimit(1)
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                TimerAddMinuteChip(model: model)
                Button(action: model.stop) { Text(TimerCopy.stopShort) }
                    .buttonStyle(CrannyChipButtonStyle(prominent: true))
                    .timerHitTarget()
                    .accessibilityLabel(Text(TimerCopy.stop))
            }
        }
    }
}

/// "Ends 14:35" while running, "Paused" while paused (the end time is fixed while running: no clock needed).
struct TimerEndLabel: View {
    let state: TimerState
    var body: some View {
        switch state.phase {
        case .running(let end): Text(TimerCopy.ends(at: TimerFormat.time(end))).lineLimit(1)
        case .paused: Text(TimerCopy.paused).lineLimit(1)
        case .idle, .done: EmptyView()
        }
    }
}

// MARK: - Controls shared by the peek row and the widget

struct TimerPauseButton: View {
    let model: TimerModel
    let size: CGFloat
    var body: some View {
        let paused = model.state.isPaused
        Button(action: model.togglePause) {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(CrannyIconButtonStyle(.plain, size: size))
        .timerHitTarget()
        .help(paused ? TimerCopy.resume : TimerCopy.pause)
        .accessibilityLabel(Text(paused ? TimerCopy.resume : TimerCopy.pause))
    }
}

struct TimerStopButton: View {
    let model: TimerModel
    let size: CGFloat
    var role: CrannyIconButtonStyle.Role = .plain
    var body: some View {
        Button(action: model.stop) { Image(systemName: "stop.fill") }
            .buttonStyle(CrannyIconButtonStyle(role, size: size))
            .timerHitTarget()
            .help(TimerCopy.stop)
            .accessibilityLabel(Text(TimerCopy.stop))
    }
}

struct TimerAddMinuteChip: View {
    let model: TimerModel
    var body: some View {
        Button(action: model.addMinute) { Text(TimerCopy.plusOneMinute) }
            .buttonStyle(CrannyChipButtonStyle())
            .timerHitTarget()
            .help(TimerCopy.addMinute)
            .accessibilityLabel(Text(TimerCopy.addMinute))
    }
}

extension View {
    /// At least 28 × 24 of clickable area around a smaller visual (DESIGN.md §16, `HitTarget.nook`).
    func timerHitTarget() -> some View {
        frame(minWidth: HitTarget.nook.width, minHeight: HitTarget.nook.height)
            .contentShape(Rectangle())
    }
}

#Preview("Band · default and the glyph form (Extra Large text)") {
    let services = CrannyServices.preview()
    let large = CrannyServices.preview()
    large.settings[CoreSettings.textSize] = .extraLarge
    let models = [TimerModel.sample(.running(left: 272, total: 300), settings: services.settings),
                  TimerModel.sample(.running(left: 272, total: 300), settings: large.settings)]
    return VStack(alignment: .leading, spacing: Space.l) {
        ForEach(Array(models.enumerated()), id: \.offset) { _, model in
            HStack(spacing: Space.l) { TimerCompactRing(model: model); TimerCompactValue(model: model) }
        }
        HStack(spacing: Space.l) {
            TimerDoneGlyph(model: .sample(.done(total: 300)))
            TimerDoneLabel(model: .sample(.done(total: 300)))
        }
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
