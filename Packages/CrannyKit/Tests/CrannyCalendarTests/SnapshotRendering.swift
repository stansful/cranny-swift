import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyCalendar

/// Visual QA without launching the app: renders the widget, the activities and the Settings rows offscreen into
/// PNGs. Opt-in (`CRANNY_SNAPSHOT_DIR=/some/dir swift test --filter CalendarSnapshots`); nothing is shown on
/// screen (the window is never ordered in) and nothing is asserted — a person looks at the files.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRANNY_SNAPSHOT_DIR"] != nil))
@MainActor struct CalendarSnapshots {
    private var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRANNY_SNAPSHOT_DIR"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    @Test func widgetSizesAndStates() async throws {
        let services = CrannyServices.preview()
        let model = CalendarModel.sample(services: services)
        let widget = CalendarWidget(model: model, services: services)
        let grid = CrannyTheme().grid
        for cells in 2...5 {
            let context = WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 24, height: 96))
            try await render("widget-\(cells)", widget.makeBody(context: context).crannyCard(cells: cells))
        }
        let states: [(String, PermissionStatus)] = [("needs-access", .notDetermined), ("denied", .denied), ("restricted", .restricted)]
        for (name, status) in states {
            let m = CalendarModel.sample(services: services, access: status)
            for cells in [2, 3] {
                let context = WidgetContext(cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 24, height: 96))
                try await render("widget-\(name)-\(cells)", CalendarWidgetView(model: m, context: context).crannyCard(cells: cells))
            }
        }
        let empty = CalendarModel.sample(services: services, events: CalendarSamples.events(around: Date()).filter { $0.id == "sample.tomorrow" })
        try await render("widget-empty-3", CalendarWidgetView(model: empty, context: WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96))).crannyCard(cells: 3))
        try await render("widget-error-3", CalendarErrorState(error: .unavailable, model: model).crannyCard(cells: 3))
        try await render("widget-hidden-3", AllCalendarsHiddenState(total: 3, model: model).crannyCard(cells: 3))
        services.settings[CalendarSettings.daysBehind] = 2
        services.settings[CalendarSettings.daysAhead] = 4
        try await render("widget-4-strip", widget.makeBody(context: WidgetContext(cells: 4, contentSize: CGSize(width: 224, height: 96))).crannyCard(cells: 4))
    }

    @Test func activities() async throws {
        let services = CrannyServices.preview()
        let soon = MeetingSoonActivity(model: .sample(services: services))
        let now = MeetingNowActivity(model: .sample(services: services))
        try await render("activity-soon", band(soon))
        try await render("activity-now", band(now))
        try await render("peek-soon", soon.peekRow().frame(width: 401, height: 52).padding(.horizontal, Space.l))
        try await render("peek-now", now.peekRow().frame(width: 401, height: 52).padding(.horizontal, Space.l))
        services.settings[CalendarSettings.inEventDisplay] = .elapsed
        try await render("activity-now-elapsed", band(now))
    }

    @Test func settingsRows() async throws {
        let services = CrannyServices.preview()
        services.settings[CalendarSettings.daysAhead] = 3                  // a changed row shows its accent dot
        services.settings[CalendarSettings.leadMinutes] = 10
        try await render("settings-pane", CalendarSettingsPane(model: .sample(services: services)).frame(width: 600, height: 720))
        try await render("settings-activities", Form {
            Section { MeetingSoonOptions(settings: services.settings) }
            Section { MeetingNowOptions(settings: services.settings) }
        }.formStyle(.grouped).frame(width: 520, height: 200))
        try await render("widget-options", CalendarWidgetOptions(settings: services.settings).frame(width: 360, height: 220))
    }

    /// Roughly the compact presentation: wings of the medium slot around a 185-pt camera housing.
    private func band(_ activity: any LiveActivity) -> some View {
        CompactSlots(layout: NotchLayout(metrics: .reference), slot: activity.slot,
                     leading: { activity.view(for: .compactLeading) }, center: { EmptyView() },
                     trailing: { activity.view(for: .compactTrailing) })
            .foregroundStyle(.white)
            .background(Capsule().fill(.black))
            .overlay(alignment: .trailing) {
                activity.view(for: .minimal).frame(width: 24, height: 24).background(Circle().fill(Color.black)).offset(x: 34)
            }
            .padding(.trailing, 40)
    }

    private func render(_ name: String, _ view: some View) async throws {
        let root = view
            .padding(16)
            .background(Color(white: 0.16))
            .crannyThemeRoot(CrannyTheme())
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for _ in 0..<5 {                                   // let tasks (MinuteClock), layout and geometry settle
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "\(name).png"))
        window.contentView = nil
    }
}
