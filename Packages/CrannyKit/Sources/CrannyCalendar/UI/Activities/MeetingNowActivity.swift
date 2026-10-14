// CrannyCalendar/UI/Activities/MeetingNowActivity.swift — "Meeting in progress" (DESIGN.md §9.2): P2 for the
// whole event. Compact: an elapsed ring in the calendar colour | "−12m" left or "+12m" elapsed (Settings ▸ Live
// Activities). Peek: ring tile · title / 2-pt progress bar and "12m left" · Join. Text and ring tick once a
// minute, only while drawn (`MinuteClock`).
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class MeetingNowActivity: LiveActivity {
    static func kind() -> ActivityKind {
        ActivityKind(id: .meetingNow, module: .calendar,
                     title: String(localized: "Meeting in progress", bundle: .module, comment: "Live Activities pane: the current-meeting activity"),
                     symbol: "calendar", defaultPriority: .ongoing, canPeekOnChange: true, peeksOnChangeByDefault: false)
    }

    @ObservationIgnored let model: CalendarModel
    init(model: CalendarModel) { self.model = model }

    let id: ActivityID = .meetingNow
    let slot: SlotWidth = .medium
    let priority: ActivityPriority = .ongoing
    var event: EventSnapshot? { model.scheduler.state.current }
    var isActive: Bool { event != nil }
    var revision: Int { model.scheduler.currentRevision }
    var palette: AmbientPalette? { event.map { .tinted($0.color) } }
    var opensWidget: WidgetID? { .calendar }
    var middleLabel: String? { event.map { CalendarFormat.title($0, redacted: model.isRedacted) } }
    var display: InEventDisplay { model.settings[CalendarSettings.inEventDisplay] }

    var accessibilityLabel: String {
        let title = event.map { CalendarFormat.title($0, redacted: model.isRedacted) } ?? ""
        return String(localized: "Meeting in progress: \(title)", bundle: .module, comment: "Meeting in progress: VoiceOver label; the argument is the event title")
    }
    var accessibilityValue: String? {
        guard let event else { return nil }
        let now = model.currentTime
        return switch display {
        case .remaining: CalendarFormat.spokenTimeLeft(minutes: max(MinuteMath.minutesUntil(event.end, from: now), 1))
        case .elapsed: CalendarFormat.spokenElapsed(minutes: MinuteMath.minutesSince(event.start, to: now))
        }
    }

    var actions: [ActivityAction] {
        guard let event else { return [] }
        var list: [ActivityAction] = []
        if model.link(for: event) != nil {
            list.append(ActivityAction(id: "join", title: String(localized: "Join meeting", bundle: .module, comment: "Calendar: Join button, VoiceOver label"),
                                       symbol: "person.2.wave.2.fill") { [model] in model.join(event) })
        }
        list.append(ActivityAction(id: "open", title: CalendarStrings.openInCalendar, symbol: "calendar") { [model] in model.openInCalendar(event) })
        return list
    }

    func compactLeading() -> some View { MeetingRing(activity: self, diameter: 16) }
    func compactTrailing() -> some View { MeetingNowValue(activity: self) }
    func minimal() -> some View { MeetingRing(activity: self, diameter: 14) }
    func peekRow() -> some View { MeetingNowPeekRow(activity: self) }
}

/// The elapsed ring in the calendar colour (compact leading slot, satellite).
private struct MeetingRing: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingNowActivity
    let diameter: CGFloat

    var body: some View {
        if let event = activity.event {
            MinuteClock(anchor: event.start) { tick in
                ProgressRing(progress: MinuteMath.progress(start: event.start, end: event.end, now: activity.model.displayNow(tick)),
                             color: theme.bandEventColor(event.color), lineWidth: StrokeWidth.ringCompact)
                    .animation(theme.animation(.contentSwap), value: tick)
            }
            .frame(width: diameter * theme.notchUnit, height: diameter * theme.notchUnit)
            .accessibilityHidden(true)
        }
    }
}

/// "−12m" (time left) or "+12m" (elapsed): one short form per setting, so the two never look alike and both fit
/// the 48u medium slot (`CalendarFormat.bandTimeLeft`; widths tested in English and Russian). It may shrink a
/// little rather than spill past the slot into the corner curve.
private struct MeetingNowValue: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingNowActivity

    var body: some View {
        if let event = activity.event {
            let remaining = activity.display == .remaining
            MinuteClock(anchor: remaining ? event.end : event.start) { tick in
                let now = activity.model.displayNow(tick)
                let minutes = remaining ? max(MinuteMath.minutesUntil(event.end, from: now), 1) : MinuteMath.minutesSince(event.start, to: now)
                Text(remaining ? CalendarFormat.bandTimeLeft(minutes: minutes) : CalendarFormat.bandTimeElapsed(minutes: minutes))
                    .crannyFont(.compact)
                    .lineLimit(1)
                    .minimumScaleFactor(CalendarFormat.bandMinimumScale)
                    .contentTransition(.numericText(countsDown: remaining))
                    .animation(theme.animation(.contentSwap), value: minutes)
            }
            .foregroundStyle(theme.palette.label)
            .accessibilityHidden(true)
        }
    }
}

private struct MeetingNowPeekRow: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingNowActivity

    var body: some View {
        if let event = activity.event {
            let model = activity.model
            let remaining = activity.display == .remaining
            MinuteClock(anchor: remaining ? event.end : event.start) { tick in
                let now = model.displayNow(tick)
                let progress = MinuteMath.progress(start: event.start, end: event.end, now: now)
                MeetingPeekLayout {
                    RingTile(color: event.color, progress: progress)
                } title: {
                    Text(CalendarFormat.title(event, redacted: model.isRedacted))
                } detail: {
                    HStack(spacing: Space.m) {
                        LevelBar(value: progress, tint: theme.palette.success, thickness: 2)
                            .frame(maxWidth: 120)
                        Text(remaining ? CalendarFormat.timeLeft(minutes: max(MinuteMath.minutesUntil(event.end, from: now), 1))
                                       : CalendarFormat.timeElapsed(minutes: MinuteMath.minutesSince(event.start, to: now)))
                            .crannyFont(.caption)
                            .fixedSize()
                    }
                } controls: {
                    if model.link(for: event) != nil { JoinButton(size: .peek) { model.join(event) } }
                }
            }
        }
    }
}

/// 40 × 40 tile in the event's colour with the elapsed ring.
private struct RingTile: View {
    @Environment(\.cranny) private var theme
    let color: RGB
    let progress: Double
    var body: some View {
        let tint = theme.bandEventColor(color)
        RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay {
                ProgressRing(progress: progress, color: tint, lineWidth: StrokeWidth.ringCompact).padding(Space.s)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Meeting in progress · compact, satellite, peek") {
    let services = CrannyServices.preview()
    let activity = MeetingNowActivity(model: .sample(services: services))
    VStack(spacing: Space.xl) {
        HStack(spacing: 120) {
            activity.compactLeading().frame(width: 48, alignment: .trailing)
            activity.compactTrailing().frame(width: 48, alignment: .leading)
        }
        .frame(height: 32)
        activity.minimal().frame(width: 24, height: 24).background(Circle().fill(.black))
        activity.peekRow().frame(width: 401, height: 52).padding(.horizontal, Space.l)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
