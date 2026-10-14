// CrannyCalendar/CalendarCommands.swift — ⌘K (DESIGN.md §6.4): "Join next meeting" when the meeting in progress
// or the next one today has a link, and "Show today’s events" while the Calendar widget is on a page (it opens that
// page). In-memory filtering only (called per keystroke).
import CrannyCore
import Foundation

@MainActor final class CalendarCommands: PaletteCommandProvider {
    private let model: CalendarModel
    private let notch: any NotchControl

    init(model: CalendarModel, notch: any NotchControl) {
        self.model = model
        self.notch = notch
    }

    func commands(matching query: String) -> [PaletteCommand] {
        let kind = String(localized: "Calendar", bundle: .module, comment: "Calendar: module name (widget, Settings pane, ⌘K result kind)")
        var list: [PaletteCommand] = []
        if let next = model.nextJoinable {
            var keywords = [next.link.service.displayName, "zoom", "meet", "teams", "webex", "call", "video",
                            String(localized: "meeting", bundle: .module, comment: "Command palette: search keyword for Join next meeting")]
            if !model.isRedacted { keywords.append(next.event.title) }
            list.append(PaletteCommand(
                id: "calendar.joinNext",
                title: String(localized: "Join next meeting", bundle: .module, comment: "Command palette: Calendar command"),
                kind: kind, symbol: "person.2.wave.2.fill", keywords: keywords) { [model] in model.join(next.event) })
        }
        // Only while a page shows the widget: opening a panel without it would show nothing.
        let pages = model.settings[CoreSettings.pages]
        if let page = pages.first(where: { $0.items.contains { $0.widget == .calendar } })?.id {
            list.append(PaletteCommand(
                id: "calendar.showToday",
                title: String(localized: "Show today’s events", bundle: .module, comment: "Command palette: Calendar command (opens the panel at the Calendar widget)"),
                kind: kind, symbol: "calendar",
                keywords: [String(localized: "agenda", bundle: .module, comment: "Command palette: search keyword for Show today's events"),
                           String(localized: "schedule", bundle: .module, comment: "Command palette: search keyword for Show today's events")]) { [notch] in
                    notch.open(page: page, focus: .calendar, reason: .keyboard)
                })
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter { command in
            command.title.localizedCaseInsensitiveContains(q) || command.kind.localizedCaseInsensitiveContains(q)
                || command.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}
