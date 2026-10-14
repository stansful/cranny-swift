// What the notch UI does NOT redo (ARCHITECTURE.md §9.2): the merged notch outline is shared by every instance of
// a frame, the progress rim ticks no faster than its line moves a pixel, the open panel's entrance ends without
// re-evaluating anything, a card is rebuilt only when what it draws changed, and band text measures keep what
// depends only on the style. Each saving must leave the output exactly as it was.
import Foundation
import os
import SwiftUI
import Testing
@testable import CrannyCore
@testable import CrannyNotchUI

// MARK: - Notch outline

/// Nonisolated like the shape: the memo is used from any thread.
@Suite("Notch outline memo") nonisolated struct NotchOutlineMemoTests {
    private let layout = NotchLayout(metrics: .reference)
    private let canvas = CGRect(x: 0, y: 0, width: 900, height: 300)

    /// A path that tells keys apart (the memo never looks inside it).
    private func marker(_ n: CGFloat) -> Path { Path(CGRect(x: n, y: 0, width: 1, height: 1)) }

    @Test func returnsTheOutlineMadeForExactlyTheseInputs() {
        let memo = NotchOutlineMemo(capacity: 4)
        let g = layout.compact(.short)
        var made = 0
        let first = memo.outline(for: g, in: canvas) { made += 1; return marker(1) }
        let again = memo.outline(for: g, in: canvas) { made += 1; return marker(2) }
        #expect(first == marker(1) && again == marker(1) && made == 1)
        // Any other size or geometry, however close, is made anew.
        #expect(memo.outline(for: g, in: canvas.offsetBy(dx: 0.5, dy: 0)) { marker(3) } == marker(3))
        var nudged = g
        nudged.earRadius += 0.001
        #expect(memo.outline(for: nudged, in: canvas) { marker(4) } == marker(4))
    }

    @Test func keepsOnlyTheLastFew() {
        let memo = NotchOutlineMemo(capacity: 2)
        let a = layout.compact(.short), b = layout.peek(rows: 1), c = layout.open(columns: 10)
        _ = memo.outline(for: a, in: canvas) { marker(1) }
        _ = memo.outline(for: b, in: canvas) { marker(2) }
        _ = memo.outline(for: c, in: canvas) { marker(3) }                     // a is the oldest: dropped
        #expect(memo.outline(for: a, in: canvas) { marker(4) } == marker(4))
        #expect(memo.outline(for: c, in: canvas) { marker(5) } == marker(3))
    }

    /// SwiftUI may ask for a shape's path off the main thread.
    @Test func isSafeFromManyThreads() {
        let memo = NotchOutlineMemo(capacity: 3)
        let geometries = [layout.hover, layout.compact(.short), layout.peek(rows: 2), layout.open(columns: 9),
                          layout.compact(.wide)]
        let wrong = OSAllocatedUnfairLock(initialState: 0)
        let canvas = canvas
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            let index = i % geometries.count
            let path = memo.outline(for: geometries[index], in: canvas) { Path(CGRect(x: index, y: 0, width: 1, height: 1)) }
            if path != Path(CGRect(x: index, y: 0, width: 1, height: 1)) { wrong.withLock { $0 += 1 } }
        }
        #expect(wrong.withLock { $0 } == 0)
    }

    /// Through `NotchShape`: the same inputs always draw the same outline, other inputs another one, whatever the
    /// shapes drawn in between (other tests draw shapes in parallel, so this holds with or without a hit).
    @Test func theShapeDrawsTheSameOutlineForTheSameInputs() {
        let shapes = [layout.hover, layout.compact(.short), layout.peek(rows: 1), layout.open(columns: 10)]
        let first = shapes.map { NotchShape($0).path(in: canvas) }
        for (index, geometry) in shapes.enumerated().reversed() {
            #expect(NotchShape(geometry).path(in: canvas) == first[index])
            #expect(NotchShape(geometry).path(in: canvas.offsetBy(dx: 10, dy: 0)) != first[index])
        }
        #expect(Set(first.map(\.description)).count == shapes.count)
    }
}

// MARK: - Progress rim

@Suite("Progress rim pacing") struct PlaybackRimPacingTests {
    /// A 290-pt compact body on a 2× display.
    private let pixels: CGFloat = 580

    @Test func aSongStillTicksEverySecond() {
        #expect(PlaybackRim.interval(duration: 210, rate: 1, pixels: pixels) == 1)
        #expect(PlaybackRim.interval(duration: 600, rate: 1, pixels: pixels) == 1)       // 1.03 s per pixel
    }

    @Test func longRecordingsTickOncePerPixelAtMost() {
        let hour = PlaybackRim.interval(duration: 3600, rate: 1, pixels: pixels)
        #expect(hour == 6)
        #expect(hour * pixels / 3600 <= 1)                                                 // never more than a pixel
        #expect(PlaybackRim.interval(duration: 3600, rate: 2, pixels: pixels) == 3)       // twice as fast
        #expect(PlaybackRim.interval(duration: 3600, rate: 0, pixels: pixels) == 6)       // as `position(at:)`
        #expect(PlaybackRim.interval(duration: 36_000, rate: 1, pixels: pixels) == PlaybackRim.maximumInterval)
    }

    @Test func degenerateInputsTickEverySecond() {
        #expect(PlaybackRim.interval(duration: 3600, rate: 1, pixels: 0) == PlaybackRim.maximumInterval)
        #expect(PlaybackRim.interval(duration: .infinity, rate: 1, pixels: pixels) == 1)
        #expect(PlaybackRim.interval(duration: .nan, rate: 1, pixels: pixels) == 1)
    }
}

// MARK: - Entrance and cards

@MainActor @Suite("Entrance and card redraws") struct CardRedrawTests {
    @Test func anEntranceEndsInPlace() {
        #expect(NotchEntrance.isEntering(nil))                                           // peek rows: always
        let entrance = NotchEntrance()
        #expect(NotchEntrance.isEntering(entrance))
        entrance.isEntering = false
        #expect(!NotchEntrance.isEntering(entrance))
    }

    @Test func aCardIsEqualWhenItDrawsTheSame() {
        let (_, registry) = previewScene(.open)
        let (_, other) = previewScene(.open)
        let item = NookItem(.media, cells: 5)
        let card = WidgetCard(item: item, registry: registry, commands: CardCommands(page: .nook))
        var rebuilt = CardCommands(page: .nook)
        rebuilt.remove = { _ in }
        rebuilt.editLayout = {}
        // New closures for the same page: the same card.
        #expect(card == WidgetCard(item: item, registry: registry, commands: rebuilt))
        // Anything it draws, or the page its commands edit, makes another card.
        #expect(card != WidgetCard(item: NookItem(.media, cells: 4), registry: registry, commands: rebuilt))
        #expect(card != WidgetCard(item: NookItem(.calendar, cells: 5), registry: registry, commands: rebuilt))
        #expect(card != WidgetCard(item: item, registry: other, commands: rebuilt))
        #expect(card != WidgetCard(item: item, registry: registry, rows: 3, commands: rebuilt))
        #expect(card != WidgetCard(item: item, registry: registry, isEditing: true, commands: rebuilt))
        #expect(card != WidgetCard(item: item, registry: registry, isFocused: true, commands: rebuilt))
        #expect(card != WidgetCard(item: item, registry: registry, commands: rebuilt, clampsToSizes: false))
        #expect(card != WidgetCard(item: item, registry: registry, commands: CardCommands(page: "page.focus")))
    }
}

// MARK: - Band text

@MainActor @Suite("Band text measures") struct BandTextMeasureTests {
    @Test func aFontIsBuiltOncePerStyleAndSize() {
        #expect(BandFont.font(.compact, size: 13) === BandFont.font(.compact, size: 13))
        #expect(BandFont.font(.compact, size: 13) !== BandFont.font(.compact, size: 14))
        #expect(BandFont.font(.compact, size: 13) !== BandFont.font(.compactLabel, size: 13))
    }

    @Test func theLastLabelIsKeptPerTextAndUnit() {
        let island = NotchLayout(metrics: PreviewDisplays.external)
        let larger = NotchLayout(metrics: NotchMetrics(hasNotch: false, notchWidth: 0, bandHeight: 38, screenWidth: 1920))
        let short = MiddleLabelMetrics.width(of: "Midnight", layout: island)
        let long = MiddleLabelMetrics.width(of: "Midnight Window", layout: island)
        #expect(short > 0 && long > short)
        #expect(MiddleLabelMetrics.width(of: "Midnight", layout: island) == short)
        #expect(MiddleLabelMetrics.width(of: "Midnight", layout: larger) > short)       // a larger band: measured again
        #expect(MiddleLabelMetrics.width(of: "Midnight Window", layout: island) == long)
    }
}

// MARK: - Hosted: widgets built per update

/// A widget that counts how often its content is built (`makeBody`).
@MainActor final class BuildCounter {
    private(set) var builds: [WidgetID: Int] = [:]
    func record(_ id: WidgetID) { builds[id, default: 0] += 1 }
}

@MainActor final class CountingWidget: NookWidget {
    let id: WidgetID
    let title = "Counting"
    let symbol = "timer"
    let summary = ""
    let sizes = WidgetSizes(minimum: 1, preferred: 3, maximum: 6)
    let counter: BuildCounter
    init(_ id: WidgetID, counter: BuildCounter) { self.id = id; self.counter = counter }
    func makeBody(context: WidgetContext) -> some View {
        counter.record(id)
        return Color.clear
    }
}

extension HostedTests {
    @MainActor @Suite("Widget builds (hosted, off-screen)") struct WidgetBuildTests {
        private let widgets: [WidgetID] = [.media, .calendar, .quickApps]                   // the Home page

        private func scene(_ phase: NotchPhase) -> (NotchSceneModel, ModuleRegistry, BuildCounter) {
            let (model, registry) = previewScene(phase)
            let counter = BuildCounter()
            for id in widgets { registry.add(widget: CountingWidget(id, counter: counter)) }
            model.openColumns = NookPreset.listener.items.reduce(0) { $0 + $1.cells }
            return (model, registry, counter)
        }

        /// The panel ends its entrance on the next main-actor turn without re-evaluating anything, so opening builds
        /// each widget once (before, the end of the entrance re-ran the panel, its header, every staggered view and
        /// the grid, and built every widget a second time in the first frames of the open spring).
        @Test func openingBuildsEachWidgetOnce() async throws {
            let (model, registry, counter) = scene(.idle)
            let (hosted, _) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            model.open = OpenState(page: .nook, reason: .click)
            model.phase = .open
            for _ in 0..<2 {                                   // the entrance ends in a task on the main actor
                hosted.settle(0.3)
                try await Task.sleep(for: .milliseconds(100))
            }
            hosted.settle(0.3)
            for id in widgets { #expect(counter.builds[id] == 1, "\(id) built \(counter.builds[id] ?? 0) times") }
        }

        /// A grid update rebuilds only the cards whose input changed (keyboard focus moved to one card).
        @Test func aGridUpdateRebuildsOnlyTheCardsThatChanged() {
            let (model, registry, counter) = scene(.open)
            let (hosted, _) = hostedCanvas(model, registry)
            defer { hosted.tearDown() }
            hosted.settle(0.3)
            let before = counter.builds
            model.open?.focus = .calendar
            hosted.settle()
            #expect(counter.builds[.calendar, default: 0] > before[.calendar, default: 0], "the focused card was not redrawn")
            #expect(counter.builds[.media] == before[.media], "an unchanged card was rebuilt")
            #expect(counter.builds[.quickApps] == before[.quickApps], "an unchanged card was rebuilt")
        }
    }
}
