import AppKit
import CrannyCore
import Foundation
import SwiftUI
import Testing
@testable import CrannyTodos

/// Opt-in visual QA without a screen: renders the widget's states to PNGs in `CRANNY_SNAPSHOTS=<directory>`
/// through an offscreen hosting view. Never runs in CI; nothing is shown on screen and nothing outside that
/// directory is written. Look at the images yourself (`30-editor-alignment`: the title must not move when
/// editing starts).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRANNY_SNAPSHOTS"] != nil))
struct TodosSnapshotTests {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRANNY_SNAPSHOTS"] ?? NSTemporaryDirectory())

    private func fixture(hidesCompleted: Bool = true) -> TodosModel {
        let services = CrannyServices.testing()
        services.settings[TodosSettings.hidesCompleted] = hidesCompleted
        let titles = ["Reply to Sam about Friday", "Water the plants", "Book train tickets to Lyon", "Back up the laptop", "Renew passport"]
        var items = titles.map { Todo(title: $0) }
        items[2].isDone = true
        return TodosModel.testing(items, services: services)
    }

    private func card(_ model: TodosModel, cells: Int, theme: CrannyTheme = CrannyTheme(),
                      isFocused: Bool = false) -> some View {
        let grid = theme.grid
        let inset = grid.density.cardPadding
        return TodosView(model: model, context: WidgetContext(
            cells: cells, contentSize: CGSize(width: grid.width(cells: cells) - 2 * inset, height: grid.height - 2 * inset),
            isFocused: isFocused))
            .crannyCard(cells: cells)
            .padding(Space.l)
            .background(Color.black)
            .crannyThemeRoot(theme)
    }

    /// Renders `view` in an offscreen window (never ordered in), so AppKit-backed parts — the scroll view, the
    /// title editor — draw too, which `ImageRenderer` cannot do.
    private func write(_ view: some View, _ name: String) async throws {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))           // one turn for onAppear / focus / geometry
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: "\(name).png"))
        window.contentView = nil
    }

    @Test func states() async throws {
        try await write(card(fixture(), cells: 3), "01-three-cells")
        try await write(card(fixture(hidesCompleted: false), cells: 3), "02-three-cells-completed-shown")
        try await write(card(fixture(), cells: 2), "03-two-cells")
        try await write(card(fixture(), cells: 4), "04-four-cells")
        try await write(card(fixture(), cells: 6), "05-six-cells")
        try await write(card(TodosModel.testing([]), cells: 3), "06-empty")
        let allDone = TodosModel.testing([Todo(title: "a", isDone: true)])
        try await write(card(allDone, cells: 3), "07-all-done")
        var xl = CrannyTheme(); xl.textSize = .extraLarge
        try await write(card(fixture(), cells: 3, theme: xl), "08-extra-large-text")
        var contrast = CrannyTheme(); contrast.increaseContrast = true
        try await write(card(fixture(hidesCompleted: false), cells: 3, theme: contrast), "09-increase-contrast")
        var lively = CrannyTheme(); lively.accent = AccentSwatch.pink.rgb
        try await write(card(fixture(hidesCompleted: false), cells: 3, theme: lively), "10-pink-accent")
        let preview = TodosModel.testing([])
        try await write(TodosView(model: preview, context: WidgetContext(cells: 3, contentSize: CGSize(width: 160, height: 96), isPreview: true))
            .crannyCard(cells: 3).padding(Space.l).background(Color.black).crannyThemeRoot(CrannyTheme()), "11-stage-samples")
        let drafting = TodosModel.testing(Array(fixture().items.prefix(2)))
        drafting.beginNew(after: nil)
        try await write(card(drafting, cells: 3), "12-new-draft")
        try await write(card(fixture(), cells: 3, isFocused: true), "13-keyboard-focus")
        var hints = NotchContext()
        hints.showsCommandHints = true
        try await write(card(fixture(), cells: 3, isFocused: true).environment(\.notchContext, hints), "14-command-hints")
    }

    @Test func rowsAndMoments() async throws {
        let model = fixture(hidesCompleted: false)
        let metrics = TodoMetrics(textSize: .standard)
        let rows = VStack(alignment: .leading, spacing: 0) {
            TodoRow(todo: model.items[0], model: model, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                    redacts: false, showsFocusRing: true, onDelete: { _ in })
            TodoRow(todo: model.items[2], model: model, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                    redacts: false, showsFocusRing: false, onDelete: { _ in })
            TodoRow(todo: model.items[1], model: model, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                    redacts: true, showsFocusRing: false, onDelete: { _ in })
            NewTodoRow(metrics: metrics, showsFocusRing: true) {}
        }
        try await write(rows.padding(.horizontal, Space.s).crannyCard(cells: 3).padding(Space.l).background(Color.black)
            .crannyThemeRoot(CrannyTheme()), "20-rows-focus-redacted")
        let motes = HStack(spacing: Space.xl) {
            ForEach([0.08, 0.25, 0.5, 0.8], id: \.self) { progress in
                ZStack {
                    Circle().fill(Color(.sRGB, red: 0.25, green: 0.6, blue: 1)).frame(width: 16, height: 16)
                    TodoMotes(progress: progress, color: Color(.sRGB, red: 0.25, green: 0.6, blue: 1), seed: 99, startRadius: 8)
                        .frame(width: 48, height: 48)
                }
            }
        }
        try await write(motes.padding(Space.l).background(Color.black).crannyThemeRoot(CrannyTheme()), "21-motes")
        let checks = HStack(spacing: Space.xl) {
            ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { t in
                ZStack {
                    Circle().fill(Color(.sRGB, red: 0.25, green: 0.6, blue: 1))
                    TodoCheckmark().trim(from: 0, to: t)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: metrics.checkLine, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 16, height: 16)
            }
        }
        try await write(checks.padding(Space.l).background(Color.black).crannyThemeRoot(CrannyTheme()), "22-check-draw")
    }

    /// A row being edited above the same row at rest: the title must not jump when editing starts.
    @Test func editorAlignment() async throws {
        let model = fixture()
        let id = model.items[1].id
        let metrics = TodoMetrics(textSize: .standard)
        let resting = TodosModel.testing([model.items[1]])
        model.beginEditing(id)
        let content = VStack(alignment: .leading, spacing: 0) {
            TodoRow(todo: model.items[1], model: model, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                    redacts: false, showsFocusRing: false, onDelete: { _ in })
            TodoRow(todo: resting.items[0], model: resting, metrics: metrics, checkStyle: .draw, isReadOnly: false,
                    redacts: false, showsFocusRing: false, onDelete: { _ in })
        }
        .frame(width: 160)
        .padding(Space.l)
        .background(Color.black)
        .crannyThemeRoot(CrannyTheme())
        try await write(content, "30-editor-alignment")
    }
}
