// CrannyTimer/UI/TimerRunningActivity.swift — "Timer" (DESIGN.md §9.2): P2 while a timer runs or is paused.
// Band: ring 16u · "4:59". Peek: ring 40 · digits / end time · ⏸ ⏹ · +1 min.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class TimerRunningActivity: LiveActivity {
    @ObservationIgnored let model: TimerModel
    init(model: TimerModel) { self.model = model }

    /// Settings ▸ Live Activities. The generic "Peek on change" is not offered: the timer's only peek is the
    /// module's own "Peek at one minute left" option, so the two toggles can never contradict each other.
    static var kind: ActivityKind {
        ActivityKind(id: .timerRunning, module: .timer, title: TimerCopy.timer, symbol: "timer",
                     defaultPriority: .ongoing, canPeekOnChange: false)
    }

    let id: ActivityID = .timerRunning
    var isActive: Bool { model.state.isCounting }
    let priority: ActivityPriority = .ongoing
    /// `.medium` ("4:59", "Done"); `.glyph` in the glyph form of Large / Extra Large text (DESIGN.md §16).
    var slot: SlotWidth { model.bandUsesGlyphForm ? .glyph : .medium }
    /// A new run and the last minute (DESIGN.md §9.2 "the last minute of a timer" undoes a swipe-up dismissal).
    var revision: Int { model.runningRevision }
    var palette: AmbientPalette? { .timer }
    var opensWidget: WidgetID? { .timer }
    var accessibilityLabel: String { model.state.isPaused ? TimerCopy.pausedLabel : TimerCopy.runningLabel }
    var accessibilityValue: String? {
        TimerCopy.left(TimerFormat.spoken(model.state.displayedSeconds(at: model.now)))
    }
    var actions: [ActivityAction] {
        let paused = model.state.isPaused
        return [
            ActivityAction(id: paused ? "resume" : "pause", title: paused ? TimerCopy.resume : TimerCopy.pause,
                           symbol: paused ? "play.fill" : "pause.fill") { [model] in model.togglePause() },
            ActivityAction(id: "stop", title: TimerCopy.stop, symbol: "stop.fill") { [model] in model.stop() },
            ActivityAction(id: "addMinute", title: TimerCopy.addMinute) { [model] in model.addMinute() },
        ]
    }

    func compactLeading() -> some View { TimerCompactRing(model: model) }
    func compactTrailing() -> some View { TimerCompactValue(model: model) }
    func minimal() -> some View { TimerCompactRing(model: model) }
    func peekRow() -> some View { TimerRunningPeekRow(model: model) }
}

#Preview("Timer running · band and peek row") {
    let model = TimerModel.sample(.running(left: 272, total: 300))
    let activity = TimerRunningActivity(model: model)
    return VStack(alignment: .leading, spacing: Space.xl) {
        HStack(spacing: Space.l) { activity.compactLeading(); activity.compactTrailing() }
        activity.peekRow().frame(width: 401, height: NotchLayout.peekRow)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
