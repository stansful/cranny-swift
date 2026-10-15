// What the notch UI does NOT redo (ARCHITECTURE.md §9.2): the merged notch outline is shared by every instance of
// a frame, the progress rim ticks no faster than its line moves a pixel, the open panel's entrance ends without
// re-evaluating anything, a card is rebuilt only when what it draws changed, band text measures keep what depends
// only on the style, and a key press (focus, hold-⌘ hints, keyboard navigation) or a new playback position
// re-evaluates only the views that show it. Each saving must leave the output exactly as it was.
import CoreGraphics
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

    @Test func degenerateInputsStayWithinTheRange() {
        #expect(PlaybackRim.interval(duration: 3600, rate: 1, pixels: 0) == PlaybackRim.maximumInterval)   // no rim
        #expect(PlaybackRim.interval(duration: .infinity, rate: 1, pixels: pixels) == 1)                 // every second
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

// MARK: - Hosted: what a key press or a media snapshot re-evaluates

/// A Now Playing source like CrannyMedia's: `isPlaying` is its own value, written only when playback starts or stops.
/// Counts the canvas's evaluations: while music plays, its keyline reads `palette` once per evaluation.
@MainActor @Observable final class CountingNowPlaying: NowPlayingSource {
    var nowPlaying: NowPlaying? {
        didSet {
            let playing = nowPlaying?.isPlaying == true
            if isPlaying != playing { isPlaying = playing }
        }
    }
    private(set) var isPlaying = false
    var artwork: CGImage?
    var trackChangeCount = 0
    var audioEnergy: Double { 0 }
    @ObservationIgnored private(set) var paletteReads = 0
    var palette: AmbientPalette? {
        paletteReads += 1
        return .afterglow
    }
    func send(_ command: MediaCommand) async -> Bool { false }
}

/// The primary activity, ranked like Now Playing (ongoing while music plays). Counts how often its priority is read:
/// once per evaluation of the canvas and once per evaluation of the open header.
@MainActor @Observable final class TrackActivity: LiveActivity {
    let id: ActivityID = .nowPlaying
    let isActive = true
    let slot: SlotWidth = .short
    let revision = 0
    @ObservationIgnored let source: CountingNowPlaying
    @ObservationIgnored private(set) var priorityReads = 0
    init(source: CountingNowPlaying) { self.source = source }
    var priority: ActivityPriority {
        priorityReads += 1
        return source.isPlaying ? .ongoing : .passive
    }
    var accessibilityLabel: String { "Track" }
    var accessibilityValue: String? { nil }
    func compactLeading() -> some View { EmptyView() }
    func compactTrailing() -> some View { EmptyView() }
    func minimal() -> some View { EmptyView() }
    func peekRow() -> some View { EmptyView() }
}

/// A widget that shows the playback position, like the Media widget. Its builds count under its ID, the evaluations
/// of the line that shows the track under `TrackWidget.line`.
@MainActor final class TrackWidget: NookWidget {
    static let line: WidgetID = "track.line"
    let id: WidgetID
    let title = "Track"
    let symbol = "music.note"
    let summary = ""
    let sizes = WidgetSizes(minimum: 1, preferred: 3, maximum: 6)
    let source: CountingNowPlaying
    let counter: BuildCounter
    init(_ id: WidgetID, source: CountingNowPlaying, counter: BuildCounter) {
        self.id = id; self.source = source; self.counter = counter
    }
    func makeBody(context: WidgetContext) -> some View {
        counter.record(id)
        return TrackLine(source: source, counter: counter)
    }
}

struct TrackLine: View {
    let source: CountingNowPlaying
    let counter: BuildCounter
    var body: some View {
        counter.record(TrackWidget.line)
        return Text(verbatim: "\(source.nowPlaying?.elapsed ?? 0)")
    }
}

/// The interaction entries as the probe's content last saw them.
nonisolated struct InteractionFacts: Equatable {
    var focusedWidget: WidgetID?
    var showsCommandHints = false
    var keyboardNavigation = false
    var isOnScreen = true
}

/// A widget whose content reads the interaction entries, as focus rings and key caps do. Its builds count under its ID.
@MainActor final class InteractionProbeWidget: NookWidget {
    let id: WidgetID
    let title = "Probe"
    let symbol = "timer"
    let summary = ""
    let sizes = WidgetSizes(minimum: 1, preferred: 3, maximum: 6)
    let counter: BuildCounter
    let seen: InteractionLog
    init(_ id: WidgetID, counter: BuildCounter, seen: InteractionLog) { self.id = id; self.counter = counter; self.seen = seen }
    func makeBody(context: WidgetContext) -> some View {
        counter.record(id)
        return InteractionProbe(seen: seen)
    }
}

@MainActor final class InteractionLog {
    var last = InteractionFacts()
}

struct InteractionProbe: View {
    @Environment(\.notchFocusedWidget) private var focusedWidget
    @Environment(\.notchShowsCommandHints) private var showsCommandHints
    @Environment(\.notchKeyboardNavigation) private var keyboardNavigation
    @Environment(\.notchIsOnScreen) private var isOnScreen
    let seen: InteractionLog
    var body: some View {
        seen.last = InteractionFacts(focusedWidget: focusedWidget, showsCommandHints: showsCommandHints,
                                     keyboardNavigation: keyboardNavigation, isOnScreen: isOnScreen)
        return Color.clear
    }
}

extension HostedTests {
    @MainActor @Suite("Interaction and media redraws (hosted, off-screen)") struct InteractionRedrawTests {
        /// The open Home page: a counting widget, a widget that shows the track and a probe that reads the interaction
        /// entries; music plays and Now Playing is the primary activity.
        private struct Scene {
            let model: NotchSceneModel
            let registry: ModuleRegistry
            let counter = BuildCounter()
            let seen = InteractionLog()
            let source = CountingNowPlaying()
            let activity: TrackActivity

            init() {
                let (model, registry) = previewScene(.open)
                self.model = model
                self.registry = registry
                activity = TrackActivity(source: source)
                source.nowPlaying = Scene.track(elapsed: 10)
                registry.services.nowPlaying = source
                registry.add(widget: CountingWidget(.media, counter: counter))
                registry.add(widget: TrackWidget(.calendar, source: source, counter: counter))
                registry.add(widget: InteractionProbeWidget(.quickApps, counter: counter, seen: seen))
                model.openColumns = NookPreset.listener.items.reduce(0) { $0 + $1.cells }
                model.sampleActivities[activity.id] = activity
                model.primary = activity.id
            }

            static func track(elapsed: TimeInterval, playing: Bool = true) -> NowPlaying {
                NowPlaying(bundleID: "com.apple.Music", title: "Midnight Window", artist: "The Example Band", duration: 200,
                           elapsed: elapsed, timestamp: Date(timeIntervalSince1970: 1_000_000), rate: playing ? 1 : 0,
                           isPlaying: playing)
            }

            func builds(_ id: WidgetID) -> Int { counter.builds[id, default: 0] }
            var widgetBuilds: [Int] { [WidgetID.media, .calendar, .quickApps].map(builds) }
        }

        private func host(_ scene: Scene) -> Hosted<some View> {
            let (hosted, _) = hostedCanvas(scene.model, scene.registry)
            hosted.settle(0.3)
            return hosted
        }

        /// The owner moves the keyboard focus (Tab, type-to-capture): only the widget that gains it and the one that
        /// loses it are built again, and the canvas is not re-evaluated. The views that show focus see the move.
        @Test func aFocusMoveRebuildsOnlyTheWidgetsWhoseFocusChanged() {
            let scene = Scene()
            let hosted = host(scene)
            defer { hosted.tearDown() }
            let canvas = scene.source.paletteReads
            var media = scene.builds(.media), calendar = scene.builds(.calendar), probe = scene.builds(.quickApps)

            scene.model.focusedWidget = .calendar
            hosted.settle()
            #expect(scene.seen.last.focusedWidget == .calendar)
            #expect(scene.builds(.calendar) > calendar, "the widget that gained focus was not told")
            #expect(scene.builds(.media) == media, "a widget whose focus did not change was rebuilt")
            #expect(scene.builds(.quickApps) == probe, "a widget whose focus did not change was rebuilt")
            #expect(scene.source.paletteReads == canvas, "the canvas was re-evaluated")

            media = scene.builds(.media); calendar = scene.builds(.calendar)
            scene.model.focusedWidget = .media
            hosted.settle()
            #expect(scene.builds(.media) > media && scene.builds(.calendar) > calendar)
            #expect(scene.builds(.quickApps) == probe, "a widget whose focus did not change was rebuilt")
        }

        /// Holding ⌘ shows the key caps: no widget is built again, and neither the canvas nor the header is
        /// re-evaluated (only the key caps and the views that read the hints are).
        @Test func aHintToggleRebuildsNoWidgetNorTheCanvasOrTheHeader() {
            let scene = Scene()
            let hosted = host(scene)
            defer { hosted.tearDown() }
            let builds = scene.widgetBuilds, canvas = scene.source.paletteReads, priority = scene.activity.priorityReads

            scene.model.showsCommandHints = true
            hosted.settle()
            #expect(scene.seen.last.showsCommandHints)
            #expect(scene.widgetBuilds == builds, "a widget was rebuilt")
            #expect(scene.source.paletteReads == canvas, "the canvas was re-evaluated")
            #expect(scene.activity.priorityReads == priority, "the canvas or the header was re-evaluated")

            scene.model.showsCommandHints = false
            hosted.settle()
            #expect(!scene.seen.last.showsCommandHints)
            #expect(scene.widgetBuilds == builds && scene.activity.priorityReads == priority)
        }

        /// A key press turns the focus rings on: the card chrome draws them, no widget is built again and the canvas
        /// is not re-evaluated. Occlusion reaches the widgets the same way (running rings pause).
        @Test func keyboardNavigationAndVisibilityRebuildNoWidget() {
            let scene = Scene()
            let hosted = host(scene)
            defer { hosted.tearDown() }
            let builds = scene.widgetBuilds, canvas = scene.source.paletteReads, priority = scene.activity.priorityReads

            scene.model.keyboardNavigation = true
            hosted.settle()
            #expect(scene.seen.last.keyboardNavigation)
            #expect(scene.widgetBuilds == builds, "a widget was rebuilt")
            #expect(scene.source.paletteReads == canvas && scene.activity.priorityReads == priority,
                    "the canvas or the header was re-evaluated")

            scene.model.isVisibleOnScreen = false
            hosted.settle()
            #expect(!scene.seen.last.isOnScreen)
            #expect(scene.widgetBuilds == builds, "a widget was rebuilt")
        }

        /// A new playback position (a seek, a new anchor) updates the view that shows the track, not the canvas (its
        /// keyline needs only whether music plays) nor the open header (the primary's priority needs the same).
        @Test func aNowPlayingSnapshotReEvaluatesOnlyTheViewsThatShowTheTrack() {
            let scene = Scene()
            let hosted = host(scene)
            defer { hosted.tearDown() }
            let line = scene.builds(TrackWidget.line), builds = scene.widgetBuilds
            let canvas = scene.source.paletteReads, priority = scene.activity.priorityReads
            #expect(canvas > 0 && priority > 0)                       // the probes count: music plays, a primary leads

            scene.source.nowPlaying = Scene.track(elapsed: 42)
            hosted.settle()
            #expect(scene.builds(TrackWidget.line) > line, "the view that shows the track was not updated")
            #expect(scene.widgetBuilds == builds, "a widget was rebuilt")
            #expect(scene.source.paletteReads == canvas, "the canvas was re-evaluated")
            #expect(scene.activity.priorityReads == priority, "the canvas or the header was re-evaluated")

            // Pausing changes the keyline and the primary's priority: both are evaluated again.
            scene.source.nowPlaying = Scene.track(elapsed: 42, playing: false)
            hosted.settle()
            #expect(scene.activity.priorityReads > priority)
        }
    }
}
