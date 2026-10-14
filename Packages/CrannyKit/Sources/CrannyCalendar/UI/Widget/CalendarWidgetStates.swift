// CrannyCalendar/UI/Widget/CalendarWidgetStates.swift — every state of the widget besides its list (DESIGN.md
// §6.8, §7.2): needs permission ("Show your events": the only place Cranny asks for Calendar access), denied,
// restricted, loading (nothing for 300 ms, then a quiet ring), error with retry, all calendars hidden, and the
// empty day ("No more events today" + tomorrow's first event).
import CrannyCore
import Foundation
import SwiftUI

/// No access yet, denied or restricted.
struct CalendarAccessState: View {
    @Environment(\.cranny) private var theme
    let status: PermissionStatus
    let model: CalendarModel
    let context: WidgetContext

    var body: some View {
        Group {
            switch status {
            case .denied:
                state(.needsPermission,
                      message: String(localized: "Calendar access is off.", bundle: .module, comment: "Calendar widget: access was denied in System Settings"),
                      compactMessage: String(localized: "Access is off", bundle: .module, comment: "Calendar widget, 2 cells: access was denied (very short)"),
                      action: String(localized: "Open System Settings", bundle: .module, comment: "Calendar widget: button that opens Privacy & Security ▸ Calendars"),
                      perform: { model.store.openPrivacySettings() })
            case .restricted:
                state(.empty,
                      message: String(localized: "Calendar access is restricted on this Mac.", bundle: .module, comment: "Calendar widget: access blocked by a profile or parental controls"),
                      compactMessage: nil, action: nil, perform: nil)
            default:
                state(.needsPermission,
                      message: String(localized: "See your day and join meetings from here.", bundle: .module, comment: "Calendar widget: why to allow calendar access (one line)"),
                      compactMessage: nil,
                      action: String(localized: "Show your events", bundle: .module, comment: "Calendar widget: button that asks for calendar access"),
                      perform: requestAction)
            }
        }
        // The user may have changed access in System Settings while Cranny ran (never prompts).
        .onAppear { if !context.isPreview { model.store.refreshAccess() } }
    }

    /// The prompt, never on a preview stage.
    private var requestAction: (@MainActor () -> Void)? {
        guard !context.isPreview else { return nil }
        let store = model.store
        return { Task { await store.requestAccess() } }
    }

    @ViewBuilder
    private func state(_ kind: WidgetStateView.Kind, message: String, compactMessage: String?, action: String?,
                       perform: (@MainActor () -> Void)?) -> some View {
        if context.cells <= 2 {
            CompactStateTile(note: action == nil ? nil : compactMessage, message: action ?? message, isAction: action != nil, perform: perform)
        } else {
            WidgetStateView(kind, symbol: "calendar", message: message, actionTitle: action, action: perform)
        }
    }
}

/// The 2-cell form of a state: the whole card is the button (there is no room for a sentence and a capsule).
private struct CompactStateTile: View {
    @Environment(\.cranny) private var theme
    @State private var hovered = false
    /// A short line above the action ("Access is off").
    let note: String?
    let message: String
    let isAction: Bool
    let perform: (@MainActor () -> Void)?

    var body: some View {
        let p = theme.palette
        let content = VStack(spacing: Space.s) {
            Image(systemName: "calendar")
                .font(CrannyTextStyle.numeral.font(textSize: theme.textSize).weight(.medium))   // Nook symbols: medium
                .foregroundStyle(p.secondaryLabel)
            if let note {
                Text(note).crannyFont(.caption).foregroundStyle(p.tertiaryLabel).lineLimit(1)
            }
            Text(message)
                .crannyFont(.caption).fontWeight(isAction ? .semibold : .medium)
                .foregroundStyle(isAction ? p.info : p.secondaryLabel)              // links are `info` (DESIGN.md §2.1)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let perform {
            Button(action: perform) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: theme.grid.innerRadius, style: .continuous)
                    .fill(hovered ? p.control : .clear).padding(-Space.xs))
                .onHover { hovered = $0 }
                .animation(theme.animation(.hover), value: hovered)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

/// Nothing for 300 ms, then a quiet 2.5-pt ring (DESIGN.md §6.8).
struct CalendarLoadingState: View {
    @State private var visible = false
    var body: some View {
        WidgetStateView(.loading, symbol: "calendar",
                        message: String(localized: "Loading events…", bundle: .module, comment: "Calendar widget: loading state (shown after 300 ms)"))
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                visible = true
            }
    }
}

struct CalendarErrorState: View {
    let error: CalendarError
    let model: CalendarModel
    var body: some View {
        WidgetStateView(.error, symbol: "exclamationmark", message: error.errorDescription ?? "",
                        actionTitle: String(localized: "Try again", bundle: .module, comment: "Calendar widget: retry after an error"),
                        action: { Task { await model.store.reload() } })
    }
}

/// "Calendars: 0 of 5 shown · Choose…".
struct AllCalendarsHiddenState: View {
    let total: Int
    let model: CalendarModel
    var body: some View {
        WidgetStateView(.empty, symbol: "calendar",
                        message: String(localized: "Calendars: 0 of \(total) shown", bundle: .module, comment: "Calendar widget: every calendar is hidden in Settings"),
                        actionTitle: String(localized: "Choose…", bundle: .module, comment: "Calendar widget: opens Settings ▸ Calendar to pick calendars"),
                        action: { model.openCalendarSettings() })
    }
}

/// Today has nothing left: say so, and show tomorrow's first event (tertiary).
struct EmptyDayState: View {
    @Environment(\.cranny) private var theme
    let isToday: Bool
    let tomorrowFirst: EventSnapshot?
    let redacted: Bool

    var body: some View {
        let p = theme.palette
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(isToday ? String(localized: "No more events today", bundle: .module, comment: "Calendar widget: empty state for the rest of today")
                         : String(localized: "No events", bundle: .module, comment: "Calendar widget: empty state for another day"))
                .crannyFont(.callout)
                .foregroundStyle(p.secondaryLabel)
            if isToday, let event = tomorrowFirst {
                HStack(spacing: Space.s) {
                    CalendarMark(color: event.color, height: 12, dimmed: true)
                    Text(tomorrowLine(event))
                        .crannyFont(.caption)
                        .foregroundStyle(p.tertiaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func tomorrowLine(_ event: EventSnapshot) -> String { Self.tomorrowLine(event, redacted: redacted) }

    /// "Tomorrow 10:00 · Planning" (also the 2-cell form's VoiceOver label).
    static func tomorrowLine(_ event: EventSnapshot, redacted: Bool) -> String {
        let time = CalendarFormat.time(event.start), title = CalendarFormat.title(event, redacted: redacted)
        return String(localized: "Tomorrow \(time) · \(title)", bundle: .module, comment: "Calendar widget: tomorrow's first event under \"No more events today\"")
    }
}

#Preview("States · 3 cells") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let context = WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96))
    return HStack(spacing: Space.m) {
        CalendarAccessState(status: .notDetermined, model: model, context: context).crannyCard(cells: 3)
        CalendarAccessState(status: .denied, model: model, context: context).crannyCard(cells: 3)
        CalendarErrorState(error: .unavailable, model: model).crannyCard(cells: 3)
        AllCalendarsHiddenState(total: 5, model: model).crannyCard(cells: 3)
        EmptyDayState(isToday: true, tomorrowFirst: CalendarSamples.events(around: Date()).last { $0.isTimed }, redacted: false)
            .crannyCard(cells: 3)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}

#Preview("States · 2 cells") {
    let services = CrannyServices.preview()
    let model = CalendarModel.sample(services: services)
    let context = WidgetContext(cells: 2, contentSize: CGSize(width: 96, height: 96))
    return HStack(spacing: Space.m) {
        CalendarAccessState(status: .notDetermined, model: model, context: context).crannyCard(cells: 2)
        CalendarAccessState(status: .denied, model: model, context: context).crannyCard(cells: 2)
        CalendarAccessState(status: .restricted, model: model, context: context).crannyCard(cells: 2)
    }
    .padding()
    .background(.black)
    .crannyThemeRoot(CrannyTheme())
}
