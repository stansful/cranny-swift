// CrannyOnboarding/Stage/StageScene.swift — the owner of the onboarding stage's `NotchSceneModel`
// (ARCHITECTURE.md §4.12: only the owner writes it). Theme and layout come from `ThemeResolver`, exactly as for
// the real panel and the Settings stage; sample activities go in `sampleActivities` (D21).
import AppKit
import CrannyCore
import CrannyNotchUI
import Foundation
import Observation

@MainActor @Observable final class StageScene {
    /// What the stage shows for a step.
    enum Presentation: Equatable, Sendable {
        case idle
        /// Step 1: the "Hi" plays in the wings, as on the real notch.
        case greeting
        /// The open panel with the Home layout.
        case open
        /// Step 3: the practice notch (a sample track in the wings when something plays).
        case practice(withTrack: Bool)
    }

    let model: NotchSceneModel
    private(set) var presentation: Presentation = .idle
    /// The stage shows a camera housing (else a floating island or an attached tab).
    var hasNotch: Bool { model.layout.metrics.hasNotch }
    /// What the canvas draws now (also for tests, which do not import CrannyNotchUI).
    var phase: NotchPhase { model.phase }
    var primary: ActivityID? { model.primary }
    var openColumns: Int { model.openColumns }
    var gestureTranslation: CGSize { model.gestureTranslation }
    var isPreview: Bool { model.context.isPreview }
    var delight: DelightMoment? { model.delight }
    var delightSerial: Int { model.delightSerial }

    @ObservationIgnored private let registry: ModuleRegistry
    @ObservationIgnored private let greeting: StageGreeting
    @ObservationIgnored private var sequence: Task<Void, Never>?
    /// The media module's sample Now Playing (never the real one), when it provides a sample.
    @ObservationIgnored private var trackSample: (any LiveActivity)?
    @ObservationIgnored private var reduceMotion = false
    /// "First light" plays once, the first time the stage opens (DESIGN.md §5.5).
    @ObservationIgnored private var hasPlayedFirstLight = false

    init(registry: ModuleRegistry, layout: NotchLayout, theme: CrannyTheme, ambient: AmbientPalette, greeting: String) {
        self.registry = registry
        self.greeting = StageGreeting(label: greeting)
        model = NotchSceneModel(layout: layout, theme: theme)
        model.ambient = ambient
        model.context.isPreview = true                      // no hardware, no prompts, no writes (WidgetContext)
        model.context.phase = .idle
        model.context.layout = layout
        model.sampleActivities[StageGreeting.activityID] = self.greeting
        refreshLayout()
    }

    /// A stage for the display that carries Cranny's notch: the first one with a camera housing, else the
    /// primary display (where the panel goes in clamshell mode, ARCHITECTURE.md §4.9).
    static func live(registry: ModuleRegistry, greeting: String) -> StageScene {
        let settings = registry.services.settings
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        let metrics = screen.map(NotchMetrics.measure) ?? .reference
        var style = settings[CoreSettings.noNotchStyle]
        if let screen, let key = ThemeResolver.displayKey(screen), let own = settings[CoreSettings.perDisplay][key]?.style { style = own }
        if style == .off { style = .floatingIsland }        // the stage always shows something
        let layout = ThemeResolver.layout(metrics: metrics, displayModel: screen.flatMap(ThemeResolver.displayModelKey),
                                          style: style, settings: settings, textSize: settings[CoreSettings.textSize],
                                          density: settings[CoreSettings.density], widgetStyle: settings[CoreSettings.widgetStyle])
        let theme = ThemeResolver.theme(settings: settings, albumAccent: registry.services.nowPlaying?.palette?.accent,
                                        notchUnit: metrics.unit, isFloatingDisplay: layout.isFloating)
        let ambient = ThemeResolver.ambientPalette(topActivity: nil, accent: settings[CoreSettings.accent],
                                                   systemAccent: AccentResolver.systemAccent())
        return StageScene(registry: registry, layout: layout, theme: theme, ambient: ambient, greeting: greeting)
    }

    // MARK: Presentations

    /// Shows a step's presentation. `reduceMotion` holds still frames instead of playing sequences.
    func show(_ presentation: Presentation, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        sequence?.cancel()
        self.presentation = presentation
        setGesture(.zero)
        switch presentation {
        case .idle:
            setPhase(.idle)
        case .greeting:
            greet(reduceMotion: reduceMotion)
        case .open:
            setOpen(true)
        case .practice(let withTrack):
            trackSample = withTrack ? registry.activity(.nowPlaying)?.makeSample?() : nil
            if let trackSample {
                model.sampleActivities[trackSample.id] = trackSample
                setCompact(trackSample)
            } else {
                setPhase(.idle)
            }
        }
    }

    /// Step 1: idle → "Hi" in the wings → idle, in time with the real notch's flash. Under Reduce Motion the
    /// "Hi" frame holds.
    func greet(reduceMotion: Bool) {
        sequence?.cancel()
        if reduceMotion {
            setCompact(greeting)
            return
        }
        setPhase(.idle)
        sequence = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.setCompact(self.greeting)
            try? await Task.sleep(for: .seconds(HoverIntent.peekAutoDismiss))
            guard !Task.isCancelled else { return }
            self.setPhase(.idle)
        }
    }

    /// Opens or closes the stage notch (step 2 mirrors the real one; step 3 practises).
    func setOpen(_ open: Bool) {
        if open {
            refreshLayout()
            model.open = OpenState(page: .nook, reason: .programmatic)
            setPhase(.open)
            playFirstLight()
        } else if let trackSample, case .practice(true) = presentation {
            setCompact(trackSample)
        } else {
            setPhase(.idle)
        }
    }

    /// Live rubber-band offset (already rubber-banded; ARCHITECTURE.md §4.12).
    func setGesture(_ translation: CGSize) {
        if model.gestureTranslation != translation { model.gestureTranslation = translation }
    }

    /// A practice sideways swipe: the sample track handles it (samples never touch real media).
    func swipeTrack(_ gesture: ActivityGesture) {
        _ = trackSample?.handle(gesture)
    }

    /// Re-reads the Home layout (a preset was picked) so the open width follows.
    func refreshLayout() {
        let items = PresetLayout.homeItems(registry.services.settings[CoreSettings.pages])
        let sizes = Dictionary(registry.widgets.map { ($0.id, $0.sizes) }, uniquingKeysWith: { first, _ in first })
        let columns = PresetLayout.columns(of: items, sizes: sizes)
        if model.openColumns != columns { model.openColumns = columns }
    }

    func stop() {
        sequence?.cancel()
        sequence = nil
    }

    // MARK: Scale

    /// The stage draws closed and compact at 1:1 (crisp type) and scales the open panel down to fit.
    var scale: CGFloat { Self.fitScale(for: model.geometry, in: WelcomeMetrics.stageSize) }

    nonisolated static func fitScale(for geometry: NotchGeometry, in size: CGSize) -> CGFloat {
        let margin = WelcomeMetrics.stageMargin
        guard geometry.outerWidth > 0, geometry.bottom > 0 else { return 1 }
        let fit = min((size.width - 2 * margin) / geometry.outerWidth, (size.height - margin) / geometry.bottom, 1)
        return max(fit, WelcomeMetrics.minimumStageScale)
    }

    // MARK: Private

    private func setPhase(_ phase: NotchPhase) {
        if phase != .open { model.open = nil }
        if phase == .idle { model.primary = nil }
        model.phase = phase
        model.context.phase = phase
    }

    /// The owner applies the delight caps (ARCHITECTURE.md §4.12): once, never under Calm, Instant or Reduce Motion.
    private func playFirstLight() {
        guard !hasPlayedFirstLight, !reduceMotion, model.theme.motion != .calm, model.theme.motion != .instant else { return }
        hasPlayedFirstLight = true
        model.delight = .firstLight
        model.delightSerial += 1
    }

    private func setCompact(_ activity: any LiveActivity) {
        model.primary = activity.id
        model.primarySlot = activity.slot
        setPhase(.compact)
    }
}
