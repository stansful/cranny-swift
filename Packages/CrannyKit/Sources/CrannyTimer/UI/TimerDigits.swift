// CrannyTimer/UI/TimerDigits.swift — the time left as digits (DESIGN.md §7.7, §9.2), ticking with `CountdownClock`.
import CrannyCore
import Foundation
import SwiftUI

/// "4:59" for a counting timer, "0:00" when done. In the last 10 s of a running timer the digits turn `warning`
/// and pulse once per second (at most 10 pulses, WCAG 2.3.1); Calm, Instant and Reduce Motion keep the colour only.
struct TimerDigits: View {
    @Environment(\.cranny) private var theme
    let state: TimerState
    let style: CrannyTextStyle
    /// Roll each second with `.numericText(countsDown:)` (widget, peek). The band never animates per second.
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
                .contentTransition(theme.reduceMotion ? .opacity : .numericText(countsDown: true))
                .animation(rolls ? theme.animation(.contentSwap) : nil, value: seconds)
                .phaseAnimator([false, true], trigger: Self.pulseTrigger(seconds: seconds, pulsing: pulsing)) { content, up in
                    content.scaleEffect(up && pulses ? TimerMetrics.pulseScale : 1)
                } animation: { up in
                    theme.animation(up ? .press : .commit)
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
    /// keeps the last value so the end does not add an eleventh pulse.
    static func pulseTrigger(seconds: Int, pulsing: Bool) -> Int {
        if pulsing { return seconds }
        return seconds > Int(TimerLimits.pulseWindow) ? -1 : 1
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
