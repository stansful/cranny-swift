// CrannyCalendar/UI/Activities/MeetingSoonActivity.swift — "Meeting soon" (DESIGN.md §9.2): from the lead time
// (default 5 min) until the start; a P1 alert for a minute when it appears and again at one minute (two
// revisions), P2 in between. Compact: calendar dot + "in 4m" | Join pill (or the start time). Peek: tile ·
// title / time and place · Join · Dismiss.
import CrannyCore
import Foundation
import Observation
import SwiftUI

@MainActor @Observable final class MeetingSoonActivity: LiveActivity {
    static func kind() -> ActivityKind {
        ActivityKind(id: .meetingSoon, module: .calendar,
                     title: String(localized: "Meeting soon", bundle: .module, comment: "Live Activities pane: the upcoming-meeting activity"),
                     symbol: "clock", defaultPriority: .alert)
    }

    @ObservationIgnored let model: CalendarModel
    /// "Dismiss" (peek, VoiceOver) hides this stage of this event until the next meaningful change.
    private(set) var dismissedKey: String?

    init(model: CalendarModel) { self.model = model }

    let id: ActivityID = .meetingSoon
    let slot: SlotWidth = .medium
    var soon: MeetingTimeline.Soon? { model.scheduler.state.soon }
    var isActive: Bool { soon.map { $0.key != dismissedKey } ?? false }
    /// P1 for `alertHold` after each stage begins (auto-peek, VoiceOver announcement), then P2.
    var priority: ActivityPriority {
        guard let soon else { return .ongoing }
        return model.scheduler.now < soon.alertUntil ? .alert : .ongoing
    }
    var revision: Int { model.scheduler.soonRevision }
    var palette: AmbientPalette? { soon.map { .tinted($0.event.color) } }
    var opensWidget: WidgetID? { .calendar }
    var middleLabel: String? { soon.map { CalendarFormat.title($0.event, redacted: model.isRedacted) } }

    var accessibilityLabel: String {
        let title = soon.map { CalendarFormat.title($0.event, redacted: model.isRedacted) } ?? ""
        return String(localized: "Meeting soon: \(title)", bundle: .module, comment: "Meeting soon: VoiceOver label; the argument is the event title")
    }
    var accessibilityValue: String? {
        guard let event = soon?.event else { return nil }
        let now = model.currentTime
        return CalendarFormat.spokenStartsIn(minutes: max(MinuteMath.minutesUntil(event.start, from: now), 1), at: event.start)
    }

    var actions: [ActivityAction] {
        guard let event = soon?.event else { return [] }
        var list: [ActivityAction] = []
        if model.link(for: event) != nil {
            list.append(ActivityAction(id: "join", title: String(localized: "Join meeting", bundle: .module, comment: "Calendar: Join button, VoiceOver label"),
                                       symbol: "person.2.wave.2.fill") { [model] in model.join(event) })
        }
        list.append(ActivityAction(id: "open", title: CalendarStrings.openInCalendar, symbol: "calendar") { [model] in model.openInCalendar(event) })
        list.append(ActivityAction(id: "dismiss", title: CalendarStrings.dismiss, symbol: "xmark") { [weak self] in self?.dismiss() })
        return list
    }

    func dismiss() { dismissedKey = soon?.key }

    func compactLeading() -> some View { MeetingSoonLeading(activity: self) }
    func compactTrailing() -> some View { MeetingSoonTrailing(activity: self) }
    func minimal() -> some View { MeetingDot(color: soon?.event.color, diameter: 8) }
    func peekRow() -> some View { MeetingSoonPeekRow(activity: self) }
}

/// Words shared by the activities, the widget and ⌘K.
enum CalendarStrings {
    static var openInCalendar: String { String(localized: "Open in Calendar", bundle: .module, comment: "Calendar: action that shows the event in the Calendar app") }
    static var dismiss: String { String(localized: "Dismiss", bundle: .module, comment: "Meeting soon: hide this reminder until the next one") }
}

// MARK: - Compact

/// Leading slot: the calendar-colour dot and "in 4m", hugging the camera (drops the dot if the label is long).
private struct MeetingSoonLeading: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingSoonActivity

    var body: some View {
        if let event = activity.soon?.event {
            MinuteClock(anchor: event.start) { tick in
                let minutes = max(MinuteMath.minutesUntil(event.start, from: activity.model.displayNow(tick)), 1)
                let label = Text(CalendarFormat.bandStartsIn(minutes: minutes))
                    .crannyFont(.compactLabel)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(theme.animation(.contentSwap), value: minutes)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4 * theme.notchUnit) {
                        MeetingDot(color: event.color, diameter: 7)
                        label
                    }
                    label
                }
            }
            .foregroundStyle(theme.palette.label)
            .accessibilityHidden(true)
        }
    }
}

/// Trailing slot: the ONE interactive control allowed in compact (Join), else the start time.
private struct MeetingSoonTrailing: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingSoonActivity

    var body: some View {
        if let event = activity.soon?.event {
            if activity.model.link(for: event) != nil {
                JoinButton(size: .band) { activity.model.join(event) }
            } else {
                Text(CalendarFormat.bandTime(event.start))
                    .crannyFont(.compact)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(theme.palette.label)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The calendar-colour dot (compact leading slot, the satellite).
struct MeetingDot: View {
    @Environment(\.cranny) private var theme
    let color: RGB?
    let diameter: CGFloat
    var body: some View {
        Circle()
            .fill(color.map(theme.bandEventColor) ?? theme.palette.secondaryLabel)
            .frame(width: diameter * theme.notchUnit, height: diameter * theme.notchUnit)
            .accessibilityHidden(true)
    }
}

// MARK: - Peek

private struct MeetingSoonPeekRow: View {
    @Environment(\.cranny) private var theme
    let activity: MeetingSoonActivity

    var body: some View {
        if let event = activity.soon?.event {
            let model = activity.model
            let link = model.link(for: event)
            MeetingPeekLayout {
                StartTimeTile(event: event)
            } title: {
                Text(CalendarFormat.title(event, redacted: model.isRedacted))
            } detail: {
                Text(CalendarFormat.subtitle(event, link: link, redacted: model.isRedacted))
            } controls: {
                if link != nil { JoinButton(size: .peek) { model.join(event) } }
                Button { activity.dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CrannyIconButtonStyle(.plain))
                    .accessibilityLabel(Text(CalendarStrings.dismiss))
                    .help(CalendarStrings.dismiss)
            }
        }
    }
}

/// 40 × 40 tile in the event's colour with the start time ("10:30").
private struct StartTimeTile: View {
    @Environment(\.cranny) private var theme
    let event: EventSnapshot
    var body: some View {
        let color = theme.bandEventColor(event.color)
        RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous)
            .fill(color.opacity(0.2))
            .overlay(RoundedRectangle(cornerRadius: Radius.artPeek, style: .continuous).strokeBorder(color.opacity(0.45), lineWidth: 1))
            .overlay {
                Text(CalendarFormat.bandTime(event.start))
                    .crannyFont(.caption).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(theme.palette.label)
                    .padding(.horizontal, Space.xxs)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Meeting soon · compact, satellite, peek") {
    let services = CrannyServices.preview()
    let activity = MeetingSoonActivity(model: .sample(services: services))
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
