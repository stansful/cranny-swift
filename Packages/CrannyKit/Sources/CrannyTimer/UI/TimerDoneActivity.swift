// CrannyTimer/UI/TimerDoneActivity.swift — "Timer done" (DESIGN.md §9.2): P1, until dismissed or one minute.
// Band: `timer` in `warning` (+ bounce) · "Done". Peek: +1 min · Stop. Names the ember burst; the shell plays it.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class TimerDoneActivity: LiveActivity {
    @ObservationIgnored let model: TimerModel
    init(model: TimerModel) { self.model = model }

    /// Settings ▸ Live Activities. P1 alerts always peek once (ARCHITECTURE.md §4.6 step 4).
    static var kind: ActivityKind {
        ActivityKind(id: .timerDone, module: .timer, title: TimerCopy.timerDone, symbol: "timer", defaultPriority: .alert)
    }

    let id: ActivityID = .timerDone
    var isActive: Bool { model.state.isDone }
    let priority: ActivityPriority = .alert
    /// `.medium` ("4:59", "Done"); `.glyph` in the glyph form of Large / Extra Large text (DESIGN.md §16).
    var slot: SlotWidth { model.bandUsesGlyphForm ? .glyph : .medium }
    /// One per finished timer: the shell peeks, announces it to VoiceOver and plays `delight` once.
    var revision: Int { model.doneRevision }
    var expiresAt: Date? { model.state.doneAt?.addingTimeInterval(TimerLimits.doneLinger) }
    var palette: AmbientPalette? { .timer }
    var opensWidget: WidgetID? { .timer }
    var accessibilityLabel: String { TimerCopy.timerDone }
    var accessibilityValue: String? { TimerFormat.spoken(Int(model.state.total)) }
    var actions: [ActivityAction] {
        [
            ActivityAction(id: "stop", title: TimerCopy.stop, symbol: "stop.fill") { [model] in model.stop() },
            ActivityAction(id: "addMinute", title: TimerCopy.addMinute) { [model] in model.addMinute() },
        ]
    }
    var delight: DelightMoment? { .emberBurst }

    func compactLeading() -> some View { TimerDoneGlyph(model: model) }
    func compactTrailing() -> some View { TimerDoneLabel(model: model) }
    func minimal() -> some View { TimerDoneGlyph(model: model) }
    func peekRow() -> some View { TimerDonePeekRow(model: model) }
}

#Preview("Timer done · band and peek row") {
    let activity = TimerDoneActivity(model: TimerModel.sample(.done(total: 300)))
    return VStack(alignment: .leading, spacing: Space.xl) {
        HStack(spacing: Space.l) { activity.compactLeading(); activity.compactTrailing() }
        activity.peekRow().frame(width: 401, height: NotchLayout.peekRow)
    }
    .padding(Space.xl)
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
