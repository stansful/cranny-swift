// CrannyTimer/UI/TimerDial.swift — the widget's ring with what sits inside it (DESIGN.md §7.7):
//   running  "4:59" (numeral) over "Ends 14:35" (caption); hover or focus swaps the label for ⏸ ⏹
//   paused   dimmed digits over "Paused"; hover: ▶ ⏹
//   done     "0:00" in warning over ⏹ +1; ring and digits pulse twice (Reduce Motion / Calm: colour only)
//   set-up   the duration Return starts over a "Start" chip; while typing, the entry over its meaning
import CrannyCore
import Foundation
import SwiftUI

struct TimerDial: View {
    @Environment(\.cranny) private var theme
    let model: TimerModel
    let diameter: CGFloat
    /// Typed text while the face has keyboard focus ("" = not typing).
    let entry: String
    /// Hover or keyboard focus: show ⏸ ⏹ instead of the end time.
    let showsControls: Bool
    let showsFocusRing: Bool

    var body: some View {
        let state = model.state
        ZStack {
            TimerRing(state: state, diameter: diameter, lineWidth: StrokeWidth.ring)
                .notchMatched(MatchedID.timerRing)
            VStack(spacing: Space.xxs) {
                headline(state)
                    .frame(maxWidth: diameter - 2 * Space.l)
                footer(state)
                    .frame(maxWidth: diameter - 2 * Space.l)
                    .frame(height: TimerMetrics.ringButton)
            }
            .offset(y: Space.xxs)
        }
        .frame(width: diameter, height: diameter)
        .phaseAnimator([0, 1, 2, 3], trigger: model.doneRevision) { content, phase in
            content.scaleEffect(phase % 2 == 1 && pulses && state.isDone ? TimerMetrics.pulseScale : 1)
        } animation: { phase in
            theme.animation(phase % 2 == 1 ? .press : .commit)
        }
        .crannyFocusRing(showsFocusRing, radius: diameter / 2)
    }

    private var pulses: Bool { !theme.reduceMotion && theme.motion != .calm && theme.motion != .instant }

    // MARK: Big line

    @ViewBuilder private func headline(_ state: TimerState) -> some View {
        if !entry.isEmpty {
            Text(verbatim: entry)
                .crannyFont(.numeral)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(theme.palette.label)
        } else if state.phase == .idle {
            Text(verbatim: TimerFormat.clock(model.setupDuration))
                .crannyFont(.numeral)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(theme.palette.label)
                .contentTransition(theme.reduceMotion ? .opacity : .numericText())
                .animation(theme.animation(.contentSwap), value: model.setupDuration)
        } else {
            TimerDigits(state: state, style: .numeral)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: Small line (fixed height, so swapping label ⇄ controls never moves the digits)

    @ViewBuilder private func footer(_ state: TimerState) -> some View {
        let p = theme.palette
        if !entry.isEmpty {
            Group {
                if let seconds = DurationParser.seconds(from: entry) {
                    Text(TimerFormat.short(seconds)).foregroundStyle(p.secondaryLabel)
                } else {
                    Text(TimerCopy.typingHint).foregroundStyle(p.tertiaryLabel)
                }
            }
            .crannyFont(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            switch state.phase {
            case .idle:
                Button(action: model.startSetup) { Text(TimerCopy.start) }
                    .buttonStyle(CrannyChipButtonStyle(tint: p.warning, prominent: true))
            case .running, .paused:
                ZStack {
                    if showsControls {
                        HStack(spacing: Space.xs) {
                            TimerPauseButton(model: model, size: TimerMetrics.ringButton)
                            TimerStopButton(model: model, size: TimerMetrics.ringButton)
                        }
                        .transition(.opacity)
                    } else {
                        TimerEndLabel(state: state)
                            .crannyFont(.caption)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(state.isPaused ? p.secondaryLabel : p.tertiaryLabel)
                            .transition(.opacity)
                    }
                }
                .animation(theme.animation(.contentSwap), value: showsControls)
            case .done:
                // Always visible (the next step after "done"), so drawn as filled buttons, not hover glyphs.
                HStack(spacing: Space.xs) {
                    TimerStopButton(model: model, size: TimerMetrics.ringButton, role: .filled)
                    Button(action: model.addMinute) { Text(verbatim: "+1") }
                        .buttonStyle(CrannyIconButtonStyle(.filled, size: TimerMetrics.ringButton))
                        .help(TimerCopy.addMinute)
                        .accessibilityLabel(Text(TimerCopy.addMinute))
                }
            }
        }
    }
}

#Preview("Dial · every state") {
    let size: CGFloat = 88
    HStack(spacing: Space.l) {
        TimerDial(model: .sample(.running(left: 272, total: 300)), diameter: size, entry: "", showsControls: false, showsFocusRing: false)
        TimerDial(model: .sample(.running(left: 272, total: 300)), diameter: size, entry: "", showsControls: true, showsFocusRing: true)
        TimerDial(model: .sample(.paused(left: 125, total: 300)), diameter: size, entry: "", showsControls: false, showsFocusRing: false)
        TimerDial(model: .sample(.done(total: 300)), diameter: size, entry: "", showsControls: false, showsFocusRing: false)
        TimerDial(model: .sample(.setup(seconds: 360)), diameter: size, entry: "", showsControls: false, showsFocusRing: false)
        TimerDial(model: .sample(.idle), diameter: size, entry: "90s", showsControls: false, showsFocusRing: true)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
