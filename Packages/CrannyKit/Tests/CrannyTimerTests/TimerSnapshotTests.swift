import CoreGraphics
import CrannyCore
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import CrannyTimer

// Renders every timer surface with `ImageRenderer`. Always checks that each one draws; with
// CRANNY_SNAPSHOT_DIR=<directory> it also writes PNG sheets to <directory>/Timer for visual QA. Nothing is compared
// against stored images. (Copy renders in the development language here: the xctest host has no Russian
// localization; QA Russian in the app.)

@MainActor @Suite struct TimerSnapshotTests {
    @Test func widgetStatesDraw() throws {
        try render("widget-2-cells", sheet(columns: 5, [
            card(.idle), card(.running(left: 272, total: 300)), card(.running(left: 272, total: 300), focused: true),
            card(.running(left: 8, total: 60)), card(.paused(left: 125, total: 300)),
            card(.done(total: 300)), card(.setup(seconds: 360)), card(.running(left: 5400, total: 7200)),
            card(.idle, presets: [45, 90, 3600, 5400]), card(.running(left: 42, total: 1500)),
        ]))
        try render("widget-3-cells", sheet(columns: 2, [
            card(.idle, cells: 3), card(.running(left: 1499, total: 1500), cells: 3),
            card(.paused(left: 125, total: 300), cells: 3), card(.done(total: 300), cells: 3),
        ]))
    }

    @Test func activityPlacementsDraw() throws {
        let running = TimerRunningActivity(model: .sample(.running(left: 272, total: 300)))
        let lastMinute = TimerRunningActivity(model: .sample(.running(left: 42, total: 300)))
        let paused = TimerRunningActivity(model: .sample(.paused(left: 125, total: 300)))
        let done = TimerDoneActivity(model: .sample(.done(total: 300)))
        let activities: [any LiveActivity] = [running, lastMinute, paused, done]
        try render("compact", sheet(columns: 1, activities.map { band($0) }))
        try render("peek", sheet(columns: 1, activities.map { peek($0) }))
    }

    @Test func accessibilityVariantsDraw() throws {
        var contrast = CrannyTheme()
        contrast.increaseContrast = true
        var large = CrannyTheme()
        large.textSize = .extraLarge
        var rounded = CrannyTheme()
        rounded.buttonShape = .rounded
        let cases: [AnyView] = [
            card(.running(left: 272, total: 300), theme: contrast), card(.idle, theme: contrast),
            card(.running(left: 272, total: 300), theme: large), card(.idle, theme: large),
            card(.idle, theme: rounded),
        ]
        try render("widget-variants", sheet(columns: 5, cases))
        // Hover / keyboard focus: ⏸ ⏹ replace the end time; the focus ring.
        let dials: [AnyView] = [
            AnyView(TimerDial(model: .sample(.running(left: 272, total: 300)), diameter: 88, entry: "", showsControls: true,
                              showsFocusRing: true)),
            AnyView(TimerDial(model: .sample(.paused(left: 125, total: 300)), diameter: 88, entry: "", showsControls: true,
                              showsFocusRing: false)),
            AnyView(TimerDial(model: .sample(.idle), diameter: 88, entry: "90s", showsControls: false, showsFocusRing: true)),
            AnyView(TimerDial(model: .sample(.idle), diameter: 88, entry: "9x", showsControls: false, showsFocusRing: true)),
        ].map { AnyView($0.padding(Space.l).crannyCard(cells: 2).crannyThemeRoot(CrannyTheme())) }
        try render("dial-interaction", sheet(columns: 4, dials))
    }

    // MARK: Building blocks

    private func card(_ sample: TimerModel.Sample, cells: Int = 2, focused: Bool = false, presets: [Int]? = nil,
                      theme: CrannyTheme = CrannyTheme()) -> AnyView {
        let services = CrannyServices.preview()
        if let presets { services.settings[TimerSettings.presets] = presets }
        let widget = TimerWidget(model: .sample(sample, settings: services.settings), settings: services.settings,
                                 haptics: services.haptics)
        let grid = theme.grid
        let inset = grid.density.cardPadding
        let context = WidgetContext(cells: cells, rows: grid.rows,
                                    contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset),
                                    isFocused: focused)
        return AnyView(widget.makeBody(context: context).crannyCard(cells: cells).crannyThemeRoot(theme))
    }

    private func band(_ activity: any LiveActivity) -> AnyView {
        let layout = NotchLayout(metrics: .reference)
        return AnyView(
            CompactSlots(layout: layout, slot: activity.slot,
                         leading: { activity.view(for: .compactLeading) }, center: { EmptyView() },
                         trailing: { activity.view(for: .compactTrailing) })
                .foregroundStyle(.white)
                .frame(width: layout.compact(activity.slot).bodyWidth)
                .background(Color.black)
                .crannyThemeRoot(CrannyTheme()))
    }

    private func peek(_ activity: any LiveActivity) -> AnyView {
        let width = NotchLayout(metrics: .reference).peek().bodyWidth
        return AnyView(
            activity.view(for: .peekRow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: NotchLayout.peekRow)
                .padding(.horizontal, Space.l)
                .frame(width: width)
                .background(Color.black)
                .crannyThemeRoot(CrannyTheme()))
    }

    private func sheet(columns: Int, _ items: [AnyView]) -> some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return VStack(alignment: .leading, spacing: Space.l) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Space.l) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in item }
                }
            }
        }
        .padding(Space.xl)
        .background(Color.black)
    }

    private func render(_ name: String, _ view: some View) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "\(name) did not render")
        #expect(image.width > 100 && image.height > 50)
        guard let directory = SnapshotOutput.directory("Timer") else { return }
        let url = directory.appending(path: "\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
