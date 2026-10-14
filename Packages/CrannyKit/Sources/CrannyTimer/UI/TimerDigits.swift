// CrannyTimer/UI/TimerDigits.swift — the time left as digits (DESIGN.md §7.7, §9.2), ticking with `CountdownClock`.
import CrannyCore
import Foundation
import SwiftUI

/// "4:59" for a counting timer, "0:00" when done. In the last 10 s of a running timer the digits turn `warning`
/// and pulse once per second (at most 10 pulses, WCAG 2.3.1); Calm, Instant and Reduce Motion keep the colour only.
///
/// Energy: the per-second tick is NOT animated. A `.numericText` roll every second (DESIGN.md §7.7) was measured at
/// 20–27 % CPU with the open panel on screen (each roll re-renders the panel at the display rate for 0.3 s), against
/// 0.3 % for a plain swap. The digits roll only when the timer itself jumps (start, +1 min, scroll, resume) — and
/// never inside the pulse window: there the pulse's animation carried each second's change, so the roll played
/// every second again (8.6–8.7 % CPU with the open panel; 1.1–2.0 % without the roll, the pulse itself included).
struct TimerDigits: View {
    @Environment(\.cranny) private var theme
    let state: TimerState
    let style: CrannyTextStyle
    /// Roll with `.numericText(countsDown:)` when the timer jumps (widget, peek). The band never animates.
    var rolls = true
    /// The band: `warning` for the whole last minute (DESIGN.md §9.2).
    var warnsInLastMinute = false

    var body: some View {
        CountdownClock(deadline: state.endDate) { now in
            let seconds = state.displayedSeconds(at: now)
            let pulsing = state.isInPulseWindow(at: now)
            Text(verbatim: TimerFormat.clock(seconds))
                .crannyFont(style)
                .lineLimit(1)
                .foregroundStyle(color(pulsing: pulsing, lastMinute: state.isInLastMinute(at: now)))
                .contentTransition(Self.transition(pulsing: pulsing, reduceMotion: theme.reduceMotion))
                .animation(rolls ? theme.animation(.contentSwap) : nil, value: state)          // jumps only, never ticks
                .phaseAnimator([false, true], trigger: Self.pulseTrigger(seconds: seconds, pulsing: pulsing)) { content, up in
                    content.scaleEffect(Self.pulseScale(up: up, pulsing: pulsing, animates: pulses))
                } animation: { up in
                    // Short on purpose: every frame of it re-renders the panel (≈ 0.2 s per second, 10 times).
                    theme.animation(up ? .hover : .contentOut)
                }
        }
    }

    private var pulses: Bool { !theme.reduceMotion && theme.motion != .calm && theme.motion != .instant }

    private func color(pulsing: Bool, lastMinute: Bool) -> Color {
        let p = theme.palette
        if state.isDone || pulsing || (warnsInLastMinute && lastMinute) { return p.warning }
        return state.isPaused ? p.secondaryLabel : p.label
    }

    /// Changes once per second inside the pulse window and never outside it — including the step to "0:00", which
    /// keeps the last value so the end does not add an eleventh pulse. It also changes when a run LEAVES the window
    /// early (pause, "+1 min", a scroll jump); `pulseScale` makes that change play nothing.
    static func pulseTrigger(seconds: Int, pulsing: Bool) -> Int {
        if pulsing { return seconds }
        return seconds > Int(TimerLimits.pulseWindow) ? -1 : 1
    }

    /// How a change of the digits is drawn: a roll for jumps, none in the pulse window (see the energy note above).
    static func transition(pulsing: Bool, reduceMotion: Bool) -> ContentTransition {
        if pulsing { return .identity }
        return reduceMotion ? .opacity : .numericText(countsDown: true)
    }

    /// The digits' scale in one phase of a pulse: up only while the run is in its last 10 s NOW, so a trigger change
    /// caused by leaving the window is invisible, and a pulse in flight settles back when the timer is paused.
    static func pulseScale(up: Bool, pulsing: Bool, animates: Bool) -> CGFloat {
        up && pulsing && animates ? TimerMetrics.pulseScale : 1
    }
}

/// Fixed sizes of the timer's own anatomy (DESIGN.md §7.7, §9.2, §9.3). Everything else comes from Core tokens.
nonisolated enum TimerMetrics {
    /// The widget ring is the content height minus this (88 pt on a Standard 2-row card).
    static let ringInset: CGFloat = Space.m
    /// The compact ring and glyph in the band, × notch unit.
    static let compactRing: CGFloat = 16
    static let compactGlyph: CGFloat = 13
    /// The peek row visual.
    static let peekVisual: CGFloat = 40
    static let peekGlyph: CGFloat = 16
    /// Buttons inside the widget ring (⏸ ⏹, ⏹ +1).
    static let ringButton: CGFloat = 24
    /// The pulse of the digits (last 10 s) and of the ring (done, twice).
    static let pulseScale: CGFloat = 1.06
}

#Preview("Digits · running, paused, last seconds, done") {
    let now = Date()
    VStack(spacing: Space.l) {
        TimerDigits(state: TimerState(phase: .running(endDate: now.addingTimeInterval(299)), total: 300), style: .numeral)
        TimerDigits(state: TimerState(phase: .paused(remaining: 125), total: 300), style: .numeral)
        TimerDigits(state: TimerState(phase: .running(endDate: now.addingTimeInterval(9)), total: 60), style: .numeral)
        TimerDigits(state: TimerState(phase: .running(endDate: now.addingTimeInterval(42)), total: 300), style: .compact,
                    rolls: false, warnsInLastMinute: true)
        TimerDigits(state: TimerState(phase: .done(at: now), total: 300), style: .numeral)
    }
    .padding(Space.xxl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
